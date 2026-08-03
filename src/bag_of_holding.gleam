import bag_of_holding/inventory.{type Inventory, Inventory}
import bag_of_holding/storage.{type Storage, Storage}
import gleam/bool
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/result
import gleam/set.{type Set}
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
    selected_inventory: Result(String, Nil),
    selected_tab: String,
    storage: Storage,
    creating_inventory: Bool,
    deleting_inventories: Set(String),
  )
}

type Message {
  StorageLoaded(storage: Storage)
  StorageFailedToLoad(error: storage.Error)
  PersistStatusUpdated(persisted: Bool)
  PersistFailed(error: storage.Error)

  UserSelectedInventory(name: String)
  UserChangedTab(new_tab_id: String)

  UserClickedCreateNewInventory
  InventoryAdded(inventory: Inventory)
  InventoryCreationFailed(error: storage.Error)

  UserClickedDeleteInventory(inventory: String)
  InventoryDeleted(inventory: String)
  InventoryDeletionFailed(inventory: String, error: storage.Error)

  UserUpdatedInventory(name: String, update: fn(Inventory) -> Inventory)
  InventoryUpdated(old_name: String, update: fn(Inventory) -> Inventory)
  InventoryUpdateFailed(error: storage.Error)

  NoOp
}

fn init(_args: #()) -> #(Model, Effect(Message)) {
  #(Loading, storage.load(StorageLoaded, StorageFailedToLoad))
}

fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case model, message {
    _, StorageLoaded(storage:) -> #(
      Loaded(LoadedModel(
        selected_inventory: case dict.keys(storage.inventories) {
          [inventory] -> Ok(inventory)
          _ -> Error(Nil)
        },
        selected_tab: inventory_body_tab_id,
        storage:,
        creating_inventory: False,
        deleting_inventories: set.new(),
      )),
      effect.none(),
    )
    _, StorageFailedToLoad(error:) -> #(FailedToLoad(error:), effect.none())
    _, PersistStatusUpdated(persisted: True) -> #(model, effect.none())
    _, PersistStatusUpdated(persisted: False) -> #(
      FailedToLoad(error: storage.CouldNotPersist(
        "Permission denied to persist storage",
      )),
      effect.none(),
    )
    _, PersistFailed(error:) -> #(FailedToLoad(error:), effect.none())

    Loaded(model), UserSelectedInventory(name:) -> #(
      Loaded(
        LoadedModel(..model, selected_inventory: case name {
          "" -> Error(Nil)
          _ -> Ok(name)
        }),
      ),
      effect.none(),
    )
    Loaded(model), UserChangedTab(new_tab_id:) -> #(
      Loaded(LoadedModel(..model, selected_tab: new_tab_id)),
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
          selected_inventory: Ok(inventory.name),
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
          selected_inventory: Error(Nil),
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

    Loaded(model), UserUpdatedInventory(name:, update:) -> #(
      Loaded(model),
      storage.update_inventory(
        model.storage,
        name,
        update,
        InventoryUpdated,
        InventoryUpdateFailed,
      ),
    )
    Loaded(model), InventoryUpdated(old_name:, update:) -> {
      let assert Ok(old_inventory) =
        dict.get(model.storage.inventories, old_name)
      let new_inventory = update(old_inventory)
      let inventories =
        dict.insert(
          new_inventory,
          into: model.storage.inventories,
          for: new_inventory.name,
        )
      let #(inventories, selected_inventory) = case
        old_name == new_inventory.name
      {
        True -> #(inventories, model.selected_inventory)
        False -> #(
          dict.delete(old_name, from: inventories),
          Ok(new_inventory.name),
        )
      }
      #(
        Loaded(
          LoadedModel(
            ..model,
            storage: Storage(inventories:),
            selected_inventory:,
          ),
        ),
        effect.none(),
      )
    }
    _, InventoryUpdateFailed(error:) -> #(todo, todo)

    _, NoOp
    | _, UserClickedCreateNewInventory(..)
    | _, UserSelectedInventory(..)
    | _, UserChangedTab(..)
    | _, InventoryAdded(..)
    | _, UserClickedDeleteInventory(..)
    | _, InventoryDeleted(..)
    | _, InventoryDeletionFailed(..)
    | _, UserUpdatedInventory(..)
    | _, InventoryUpdated(..)
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
    selected_inventory:,
    selected_tab:,
    storage: Storage(inventories:),
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
          attribute.selected(selected_inventory == Ok(name)),
        ],
        name,
      ))
    })
  let inventory_name_options = case inventory_names {
    [] -> [
      html.option([attribute.value("")], "--No inventories found--"),
    ]
    _ -> [
      html.option(
        [
          attribute.value(""),
          attribute.selected(selected_inventory == Error(Nil)),
        ],
        "--Select an inventory--",
      ),
      ..inventory_names
    ]
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
          Ok(inventory) -> [
            event.on_click(UserClickedDeleteInventory(inventory:)),
            attribute.disabled(False),
          ]
          Error(Nil) -> [attribute.disabled(True)]
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
          inventory_name_options,
        ),
      ]),
    ]),
    case
      selected_inventory |> result.try(dict.get(model.storage.inventories, _))
    {
      Ok(inventory) -> inventory_view(inventory, selected_tab)
      Error(Nil) -> element.none()
    },
  ])
}

fn inventory_view(
  inventory: Inventory,
  selected_tab: String,
) -> Element(Message) {
  html.main([], [
    html.h1([], [
      html.input([
        attribute.type_("text"),
        attribute.minlength(1),
        attribute.value(inventory.name),
        event.on_change(fn(new_value) {
          case new_value {
            // TODO: surface the error?
            "" -> NoOp
            name ->
              UserUpdatedInventory(inventory.name, fn(inventory) {
                Inventory(..inventory, name:)
              })
          }
        }),
      ]),
    ]),
    html.label([], [
      html.text("Weight limit: "),
      html.input([
        attribute.type_("number"),
        attribute.step("1"),
        attribute.min("0"),
        attribute.value(case inventory.weight_limit {
          inventory.Pounds(lbs:) -> int.to_string(lbs)
        }),
        event.on_change(fn(weight) {
          let weight = int.parse(weight)
          case weight {
            Ok(weight) if weight >= 0 ->
              UserUpdatedInventory(inventory.name, fn(inventory) {
                Inventory(..inventory, weight_limit: inventory.Pounds(weight))
              })
            // TODO: surface the error?
            _ -> NoOp
          }
        }),
      ]),
    ]),
    html.br([]),
    html.label([], [
      html.text("Coins count towards weight limit: "),
      html.input([
        attribute.type_("checkbox"),
        attribute.checked(inventory.coins_count_towards_weight_limit),
        event.on_check(fn(new_value) {
          UserUpdatedInventory(inventory.name, fn(inventory) {
            Inventory(..inventory, coins_count_towards_weight_limit: new_value)
          })
        }),
      ]),
    ]),
    tabs(
      [
        inventory_body_tab(inventory),
        inventory_backpack_tab(inventory),
        inventory_pouch_tab(inventory),
      ],
      selected_tab,
      UserChangedTab,
    ),
  ])
}

const inventory_body_tab_id = "body"

fn inventory_body_tab(inventory: Inventory) -> Tab(Message) {
  Tab(
    id: inventory_body_tab_id,
    name: "Body",
    contents: element.fragment([html.text("body")]),
  )
}

const inventory_backpack_tab_id = "backpack"

fn inventory_backpack_tab(inventory: Inventory) -> Tab(Message) {
  Tab(
    id: inventory_backpack_tab_id,
    name: "Backpack",
    contents: element.fragment([html.text("backpack")]),
  )
}

const inventory_pouch_tab_id = "pouch"

fn inventory_pouch_tab(inventory: Inventory) -> Tab(Message) {
  Tab(
    id: inventory_pouch_tab_id,
    name: "Pouch",
    contents: element.fragment([html.text("pouch")]),
  )
}

type Tab(message) {
  Tab(id: String, name: String, contents: Element(message))
}

// Based on <https://www.w3.org/WAI/ARIA/apg/patterns/tabs/examples/tabs-automatic/>
// (2026-08-03)
/// All tabs must have unique ids.
fn tabs(
  tabs: List(Tab(message)),
  selected_tab: String,
  selected_message: fn(String) -> message,
) -> Element(message) {
  let first_tab = list.first(tabs)
  let last_tab = list.last(tabs)
  let #(buttons, panels) =
    tabs_loop(
      tabs:,
      buttons: list.new(),
      panels: list.new(),
      selected_tab:,
      selected_message:,
      prev_tab: Error(Nil),
      first_tab:,
      last_tab:,
    )

  html.div([attribute.class("tabs")], [
    html.div([attribute.role("tablist")], buttons),
    ..panels
  ])
}

fn tabs_loop(
  tabs tabs: List(Tab(message)),
  buttons buttons: List(Element(message)),
  panels panels: List(Element(message)),
  selected_tab selected_tab: String,
  selected_message selected_message: fn(String) -> message,
  prev_tab prev_tab: Result(Tab(message), Nil),
  first_tab first_tab: Result(Tab(message), Nil),
  last_tab last_tab: Result(Tab(message), Nil),
) {
  case tabs {
    [] -> #(list.reverse(buttons), list.reverse(panels))
    [tab, ..rest] -> {
      let next_tab = list.first(rest)

      let selected = tab.id == selected_tab
      let button =
        html.button(
          [
            attribute.id("tab-" <> tab.id),
            attribute.role("tab"),
            attribute.aria_selected(selected),
            attribute.autofocus(selected),
            attribute.tabindex(case selected {
              True -> 0
              False -> -1
            }),
            attribute.aria_controls("tabpanel-" <> tab.id),
            event.on_click(selected_message(tab.id)),
            event.advanced("keydown", {
              use key <- decode.field("key", decode.string)
              let selected_tab = case key {
                "ArrowLeft" -> prev_tab
                "ArrowRight" -> next_tab
                "Home" -> first_tab
                "End" -> last_tab
                _ -> Error(Nil)
              }
              case selected_tab {
                Ok(selected_tab) ->
                  decode.success(event.handler(
                    dispatch: selected_message(selected_tab.id),
                    prevent_default: True,
                    stop_propagation: True,
                  ))
                Error(Nil) ->
                  decode.failure(
                    event.handler(selected_message(tab.id), False, False),
                    "",
                  )
              }
            }),
          ],
          [html.text(tab.name)],
        )
      let panel =
        html.div(
          [
            attribute.id("tabpanel-" <> tab.id),
            attribute.role("tabpanel"),
            attribute.tabindex(0),
            attribute.aria_labelledby("tab-" <> tab.id),
            attribute.classes([#("hidden", !selected)]),
          ],
          [tab.contents],
        )
      tabs_loop(
        tabs: rest,
        buttons: [button, ..buttons],
        panels: [panel, ..panels],
        selected_tab:,
        selected_message:,
        prev_tab: Ok(tab),
        first_tab:,
        last_tab:,
      )
    }
  }
}

fn failed_to_load_view(error: storage.Error) -> Element(Message) {
  let error_message = case error {
    storage.CouldNotGetStorageManager -> "Could not get storage manager."
    storage.CouldNotPersist(error) -> "Could not persist storage: " <> error
    storage.CouldNotGetRootDirectory(error) ->
      "Could not get root directory: " <> error
    storage.FileSystemError(error) -> "File system error: " <> error
  }

  html.section([], [
    html.h2([], [html.text("Failed to load :(")]),
    html.p([], [html.text("Error: " <> error_message)]),
  ])
}
