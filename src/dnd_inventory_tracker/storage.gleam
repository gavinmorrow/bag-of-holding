import dnd_inventory_tracker/inventory.{type Inventory, Inventory}
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/result
import lustre/effect.{type Effect}
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

pub fn load(
  storage_to_message: fn(Storage) -> message,
  error_to_message: fn(Error) -> message,
) -> Effect(message) {
  effect.from(fn(dispatch) {
    let storage_promise = {
      use inventories <- promise.try_await(get_inventory_files())
      use inventories <- promise.map(
        promise.await_array(array.map(inventories, load_inventory)),
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
    promise.tap(storage_promise, fn(storage) {
      case storage {
        Ok(storage) -> dispatch(storage |> storage_to_message)
        Error(error) -> dispatch(error |> error_to_message)
      }
    })
    Nil
  })
}

fn get_inventory_files() -> Promise(
  Result(array.Array(file_system.FileHandle), Error),
) {
  use root_dir <- promise.try_await(root_dir())
  use inventories_dir <- promise.try_await(open_dir(root_dir, "inventories"))
  use #(_, inventories) <- promise.map_try(
    file_system.all_entries(inventories_dir)
    |> fs_err,
  )
  Ok(inventories)
}

fn load_inventory(
  from file: file_system.FileHandle,
) -> Promise(Result(Inventory, InventoryError)) {
  use file <- promise.try_await(
    file_system.get_file(file) |> map_err(CouldNotGetFile),
  )
  use text <- promise.map(file.text(file))
  json.parse(text, using: inventory.decoder())
  |> result.map_error(CouldNotDecode)
}

// TODO: enforce the precondition below somehow?
/// This should not be called until the previous effect has finished.
pub fn create_inventory(
  storage: Storage,
  new_inventory_message: fn(Inventory) -> message,
  error_message: fn(Error) -> message,
) -> Effect(message) {
  let name = find_unique_inventory_name(storage, starting_at: 1)
  let inventory = Inventory(..inventory.default, name:)
  effect.from(fn(dispatch) {
    let new_inventory_promise = save_inventory(inventory)
    promise.tap(new_inventory_promise, fn(res) {
      case res {
        Ok(Nil) -> dispatch(inventory |> new_inventory_message)
        Error(error) -> dispatch(error |> error_message)
      }
    })
    Nil
  })
}

fn save_inventory(inventory: Inventory) -> Promise(Result(Nil, Error)) {
  use root_dir <- promise.try_await(root_dir())
  use inventories_dir <- promise.try_await(open_dir(root_dir, "inventories"))
  use file <- promise.try_await(open_file(
    inside: inventories_dir,
    named: inventory_filename(inventory.name),
  ))
  use file <- promise.try_await(file_system.create_writable(file) |> fs_err)
  use Nil <- promise.try_await(
    file_system.write(
      file,
      inventory
        |> inventory.to_json
        |> json.to_string
        |> bit_array.from_string,
    )
    |> fs_err,
  )
  file_system.close(file)
  |> fs_err
}

pub fn delete_inventory(
  inventory: String,
  inventory_deleted_message: fn(String) -> message,
  error_message: fn(Error) -> message,
) -> Effect(message) {
  effect.from(fn(dispatch) {
    let delete_inventory_promise = delete_inventory_fs(inventory)
    promise.tap(delete_inventory_promise, fn(res) {
      case res {
        Ok(Nil) -> dispatch(inventory |> inventory_deleted_message)
        Error(error) -> dispatch(error |> error_message)
      }
    })
    Nil
  })
}

fn delete_inventory_fs(inventory: String) -> Promise(Result(Nil, Error)) {
  use root_dir <- promise.try_await(root_dir())
  use inventories_dir <- promise.try_await(open_dir(root_dir, "inventories"))
  file_system.remove_entry(
    inventories_dir,
    inventory_filename(inventory),
    False,
  )
  |> fs_err
}

fn inventory_filename(inventory_name: String) -> String {
  inventory_name <> ".inventory"
}

/// Normally, start searching at `i: 1`.
/// It will check `New Inventory <i>`, then `New Inventory <i+1>`, and so on.
fn find_unique_inventory_name(storage: Storage, starting_at i: Int) -> String {
  let name = "New Inventory " <> int.to_string(i)
  case dict.get(storage.inventories, name) {
    Ok(_) -> find_unique_inventory_name(storage, i + 1)
    Error(Nil) -> name
  }
}

fn storage_manager() -> Result(storage.StorageManager, Error) {
  storage.get()
  |> result.replace_error(CouldNotGetStorageManager)
}

fn root_dir() -> Promise(Result(file_system.DirectoryHandle, Error)) {
  case storage_manager() {
    Ok(storage_manager) ->
      storage.get_directory(storage_manager)
      |> map_err(CouldNotGetRootDirectory)
    Error(error) -> promise.resolve(Error(error))
  }
}

fn open_dir(
  inside dir: file_system.DirectoryHandle,
  named name: String,
) -> Promise(Result(file_system.DirectoryHandle, Error)) {
  file_system.get_directory_handle(dir, name, True)
  |> fs_err
}

fn open_file(
  inside dir: file_system.DirectoryHandle,
  named name: String,
) -> Promise(Result(file_system.FileHandle, Error)) {
  file_system.get_file_handle(dir, name, True)
  |> fs_err
}

fn map_err(
  promise: Promise(Result(value, a)),
  map: fn(a) -> b,
) -> Promise(Result(value, b)) {
  promise |> promise.map(result.map_error(_, map))
}

fn fs_err(
  promise: Promise(Result(value, String)),
) -> Promise(Result(value, Error)) {
  promise |> map_err(FileSystemError)
}
