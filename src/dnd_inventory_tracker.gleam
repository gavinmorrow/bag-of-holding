import dnd_inventory_tracker/inventory.{type Inventory}
import dnd_inventory_tracker/storage.{type Storage, Storage}
import gleam/bool
import gleam/dict
import gleam/list
import gleam/option.{type Option}
import gleam/set.{type Set}
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
    deleting_inventories: Set(String),
  )
}

type Message {
  StorageLoaded(storage: Storage)
  StorageFailedToLoad(error: storage.Error)

  UserSelectedInventory(name: String)

  UserClickedCreateNewInventory
  InventoryAdded(inventory: Inventory)
  InventoryCreationFailed(error: storage.Error)

  UserClickedDeleteInventory(inventory: String)
  InventoryDeleted(inventory: String)
  InventoryDeletionFailed(inventory: String, error: storage.Error)
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
        deleting_inventories: set.new(),
      )),
      effect.none(),
    )
    _, StorageFailedToLoad(error:) -> #(FailedToLoad(error:), effect.none())

    Loaded(model), UserSelectedInventory(name:) -> #(
      Loaded(
        LoadedModel(..model, selected_inventory: case name {
          "" -> option.None
          _ -> option.Some(name)
        }),
      ),
      effect.none(),
    )

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
    Loaded(model), InventoryAdded(inventory:) -> #(
      Loaded(
        LoadedModel(
          ..model,
          storage: Storage(inventories: dict.insert(
            inventory,
            for: inventory.name,
            into: model.storage.inventories,
          )),
          selected_inventory: option.Some(inventory.name),
          creating_inventory: False,
        ),
      ),
      effect.none(),
    )
    _, InventoryCreationFailed(error:) -> todo

    Loaded(model), UserClickedDeleteInventory(inventory:) -> #(
      Loaded(
        LoadedModel(
          ..model,
          selected_inventory: option.None,
          deleting_inventories: set.insert(
            inventory,
            into: model.deleting_inventories,
          ),
        ),
      ),
      storage.delete_inventory(
        inventory,
        InventoryDeleted,
        InventoryDeletionFailed(inventory, _),
      ),
    )
    Loaded(model), InventoryDeleted(inventory:) -> #(
      Loaded(
        LoadedModel(
          ..model,
          storage: Storage(dict.delete(
            inventory,
            from: model.storage.inventories,
          )),
          deleting_inventories: set.delete(
            inventory,
            from: model.deleting_inventories,
          ),
        ),
      ),
      effect.none(),
    )
    Loaded(model), InventoryDeletionFailed(inventory:, error:) -> #(
      // TODO: actually display error
      Loaded(
        LoadedModel(
          ..model,
          // TODO: should it switch selected inventory back to this one?
          deleting_inventories: set.delete(
            inventory,
            from: model.deleting_inventories,
          ),
        ),
      ),
      effect.none(),
    )

    _, UserClickedCreateNewInventory(..)
    | _, UserSelectedInventory(..)
    | _, InventoryAdded(..)
    | _, UserClickedDeleteInventory(..)
    | _, InventoryDeleted(..)
    | _, InventoryDeletionFailed(..)
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
    deleting_inventories:,
  ) = model

  let inventory_names =
    dict.keys(inventories)
    |> list.filter_map(fn(name) {
      use <- bool.guard(
        when: deleting_inventories |> set.contains(name),
        return: Error(Nil),
      )
      Ok(html.option(
        [
          attribute.value(name),
          attribute.selected(selected_inventory == option.Some(name)),
        ],
        name,
      ))
    })

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
      html.button(
        case model.selected_inventory {
          option.Some(inventory) -> [
            event.on_click(UserClickedDeleteInventory(inventory:)),
            attribute.disabled(False),
          ]
          option.None -> [attribute.disabled(True)]
        },
        [
          html.text("Delete current inventory"),
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
            _ -> [
              html.option(
                [attribute.value(""), attribute.selected(True)],
                "--Select an inventory--",
              ),
              ..inventory_names
            ]
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
