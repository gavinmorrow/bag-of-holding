import dnd_inventory_tracker/inventory.{type Inventory}
import dnd_inventory_tracker/storage.{type Storage, Storage}
import gleam/dict
import gleam/list
import gleam/option.{type Option}
import gleam/string
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", #())

  Nil
}

type Model {
  Loading
  Loaded(LoadedModel)
  FailedToLoad(error: storage.Error)
}

type LoadedModel {
  LoadedModel(
    storage: Storage,
    selected_inventory: Option(String),
    creating_inventory: Bool,
  )
}

type Message {
  StorageLoaded(storage: Storage)
  StorageFailedToLoad(error: storage.Error)
  UserClickedCreateNewInventory
  UserSelectedInventory(name: String)
  InventoryAdded(inventory: Inventory)
  InventoryCreationFailed(error: storage.Error)
}

fn init(_args: #()) -> #(Model, Effect(Message)) {
  #(Loading, storage.load(StorageLoaded, StorageFailedToLoad))
}

fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case model, message {
    _, StorageLoaded(storage:) -> #(
      Loaded(LoadedModel(
        storage:,
        selected_inventory: option.None,
        creating_inventory: False,
      )),
      effect.none(),
    )
    _, StorageFailedToLoad(error:) -> #(FailedToLoad(error:), effect.none())
    Loaded(model), UserClickedCreateNewInventory if !model.creating_inventory -> {
      #(
        Loaded(LoadedModel(..model, creating_inventory: True)),
        storage.create_inventory(
          model.storage,
          InventoryAdded,
          InventoryCreationFailed,
        ),
      )
    }
    Loaded(model), UserSelectedInventory(name:) -> #(
      Loaded(LoadedModel(..model, selected_inventory: option.Some(name))),
      effect.none(),
    )
    Loaded(LoadedModel(
      storage: Storage(inventories:),
      selected_inventory: _,
      creating_inventory: _,
    )),
      InventoryAdded(inventory:)
    -> #(
      Loaded(LoadedModel(
        storage: Storage(inventories: dict.insert(
          inventory,
          for: inventory.name,
          into: inventories,
        )),
        selected_inventory: option.Some(inventory.name),
        creating_inventory: False,
      )),
      effect.none(),
    )
    _, InventoryCreationFailed(error:) -> todo

    _, UserClickedCreateNewInventory
    | _, UserSelectedInventory(name: _)
    | _, InventoryAdded(inventory: _)
    -> #(model, effect.none())
  }
}

fn view(model: Model) -> Element(Message) {
  case model {
    Loading -> loading_view()
    Loaded(model) -> loaded_view(model)
    FailedToLoad(error:) -> failed_to_load_view(error)
  }
}

fn loading_view() -> Element(Message) {
  html.p([], [html.text("Loading...")])
}

fn loaded_view(model: LoadedModel) -> Element(Message) {
  let LoadedModel(
    storage: Storage(inventories:),
    selected_inventory:,
    creating_inventory:,
  ) = model

  let inventory_names =
    dict.keys(inventories)
    |> list.map(fn(name) { html.option([attribute.value(name)], name) })

  let inventory = case selected_inventory {
    option.Some(name) -> html.p([], [html.text("selected inventory: " <> name)])
    option.None -> element.none()
  }

  html.div([], [
    html.section([], [
      html.button(
        [
          event.on_click(UserClickedCreateNewInventory),
          attribute.disabled(creating_inventory),
        ],
        [
          html.text("Create new inventory"),
        ],
      ),
      html.div([], [
        html.label([attribute.for("inventory-select")], [
          html.text("Choose which inventory to view: "),
        ]),
        html.select(
          [
            attribute.id("inventory-select"),
            attribute.name("inventory"),
            event.on_change(UserSelectedInventory),
          ],
          case inventory_names {
            [] -> [
              html.option([attribute.value("")], "--No inventories found--"),
            ]
            _ -> inventory_names
          },
        ),
      ]),
    ]),
    inventory,
  ])
}

fn failed_to_load_view(error: storage.Error) -> Element(Message) {
  let error_message = case error {
    storage.CouldNotGetStorageManager -> "Could not get storage manager."
    storage.CouldNotGetRootDirectory(error) ->
      "Could not get root directory: " <> error
    storage.FileSystemError(error) -> "File system error: " <> error
    storage.CouldNotReadInventory(storage.CouldNotGetFile(error)) ->
      "Could not read inventory: Could not get file: " <> error
    storage.CouldNotReadInventory(storage.CouldNotDecode(decode_error)) ->
      // FIXME: this shouldn't use string.inspect
      "Could not read inventory: " <> string.inspect(decode_error)
  }

  html.section([], [
    html.h2([], [html.text("Failed to load :(")]),
    html.p([], [html.text("Error: " <> error_message)]),
  ])
}
