import dnd_inventory_tracker/inventory.{type Inventory}
import gleam/dict.{type Dict}
import gleam/javascript/array
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/result
import plinth/browser/file
import plinth/browser/file_system
import plinth/browser/storage

pub type Storage {
  Storage(inventories: Dict(String, Inventory))
}

pub type Error {
  CouldNotGetStorageManager
  CouldNotGetRootDirectory(String)
  FileSystemError(String)
  CouldNotReadInventory(InventoryError)
}

pub type InventoryError {
  CouldNotGetFile(String)
  CouldNotDecode(json.DecodeError)
}

pub fn load() -> promise.Promise(Result(Storage, Error)) {
  use storage_manager <- promise.try_await(
    storage.get()
    |> result.replace_error(CouldNotGetStorageManager)
    |> promise.resolve,
  )
  use root_dir <- promise.try_await(
    storage.get_directory(storage_manager)
    |> map_err(CouldNotGetRootDirectory),
  )
  use inventories_dir <- promise.try_await(
    file_system.get_directory_handle(root_dir, "inventories", True)
    |> map_err(FileSystemError),
  )
  use #(_, inventories) <- promise.try_await(
    file_system.all_entries(inventories_dir)
    |> map_err(FileSystemError),
  )
  use inventories <- promise.map(
    promise.await_array(
      array.map(inventories, fn(file) { load_inventory(from: file) }),
    ),
  )
  use inventories <- result.map(
    inventories
    |> array.to_list
    |> list.try_fold(from: dict.new(), with: fn(inventories, inventory) {
      case inventory {
        Ok(inventory) ->
          Ok(dict.insert(inventory, into: inventories, for: inventory.name))
        Error(error) -> Error(CouldNotReadInventory(error))
      }
    }),
  )

  Storage(inventories:)
}

fn load_inventory(
  from file: file_system.FileHandle,
) -> promise.Promise(Result(Inventory, InventoryError)) {
  use file <- promise.try_await(
    file_system.get_file(file) |> map_err(CouldNotGetFile),
  )
  use text <- promise.map(file.text(file))
  json.parse(text, using: inventory.decoder())
  |> result.map_error(CouldNotDecode)
}

fn map_err(
  promise: promise.Promise(Result(value, a)),
  map: fn(a) -> b,
) -> promise.Promise(Result(value, b)) {
  promise |> promise.map(result.map_error(_, map))
}
