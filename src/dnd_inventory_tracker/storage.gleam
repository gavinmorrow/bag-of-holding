import dnd_inventory_tracker/inventory.{type Inventory, Inventory}
import gleam/dict.{type Dict}
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/result
import lustre/effect.{type Effect}

pub type Storage {
  Storage(inventories: Dict(String, Inventory))
}

pub type Error {
  CouldNotGetStorageManager
  CouldNotGetRootDirectory(String)
  FileSystemError(String)
}

pub type InventoryError {
  CouldNotGetFile(Error)
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
        promise.await_list(list.map(inventories, load_inventory)),
      )

      let inventories =
        inventories
        |> list.fold(from: dict.new(), with: fn(inventories, inventory) {
          case inventory {
            Ok(inventory) ->
              dict.insert(inventory, into: inventories, for: inventory.name)
            Error(_error) -> {
              // TODO: handle error?
              inventories
            }
          }
        })

      Storage(inventories:) |> Ok
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

fn get_inventory_files() -> FsResult(List(FileHandle)) {
  use root_dir <- promise.try_await(get_root_directory())
  use inventories_dir <- promise.try_await(get_directory_handle(
    in: root_dir,
    named: "inventories",
    create_if_missing: True,
  ))
  use #(_, inventories) <- promise.map_try(all_entries(inventories_dir))
  Ok(inventories)
}

fn load_inventory(
  from file: FileHandle,
) -> Promise(Result(Inventory, InventoryError)) {
  use file <- promise.try_await(get_file(file) |> map_err(CouldNotGetFile))
  use text <- promise.map_try(file_text(file) |> map_err(CouldNotGetFile))
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
  write_inventory(inventory, new_inventory_message, error_message)
}

pub fn update_inventory(
  storage: Storage,
  name: String,
  update: fn(Inventory) -> Inventory,
  updated_inventory_message: fn(String, fn(Inventory) -> Inventory) -> message,
  error_message: fn(Error) -> message,
) -> Effect(message) {
  let assert Ok(inventory) = dict.get(storage.inventories, name)
    as "inventory should exist"
  let inventory = update(inventory)

  case name == inventory.name {
    True -> {
      // Just overwrite
      write_inventory(
        inventory,
        fn(_) { updated_inventory_message(name, update) },
        error_message,
      )
    }
    False -> {
      effect.from(fn(dispatch) {
        let update_promise = {
          // Rename the file, via deleting and creating
          use Nil <- promise.try_await(delete_inventory_fs(name))
          write_inventory_fs(inventory)
        }
        promise.tap(update_promise, fn(res) {
          case res {
            Ok(Nil) -> dispatch(updated_inventory_message(name, update))
            Error(error) -> dispatch(error_message(error))
          }
        })
        Nil
      })
    }
  }
}

fn write_inventory(
  inventory: Inventory,
  new_inventory_message: fn(Inventory) -> message,
  error_message: fn(Error) -> message,
) -> Effect(message) {
  effect.from(fn(dispatch) {
    let new_inventory_promise = write_inventory_fs(inventory)
    promise.tap(new_inventory_promise, fn(res) {
      case res {
        Ok(Nil) -> dispatch(inventory |> new_inventory_message)
        Error(error) -> dispatch(error |> error_message)
      }
    })
    Nil
  })
}

fn write_inventory_fs(inventory: Inventory) -> FsResult(Nil) {
  use root_dir <- promise.try_await(get_root_directory())
  use inventories_dir <- promise.try_await(get_directory_handle(
    in: root_dir,
    named: "inventories",
    create_if_missing: True,
  ))
  use file <- promise.try_await(get_file_handle(
    in: inventories_dir,
    named: inventory_filename(inventory.name),
    create_if_missing: True,
  ))
  write(
    inventory
      |> inventory.to_json
      |> json.to_string,
    to: file,
  )
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

fn delete_inventory_fs(inventory: String) -> FsResult(Nil) {
  use root_dir <- promise.try_await(get_root_directory())
  use inventories_dir <- promise.try_await(get_directory_handle(
    in: root_dir,
    named: "inventories",
    create_if_missing: False,
  ))
  remove_entry(
    in: inventories_dir,
    named: inventory_filename(inventory),
    recursive: False,
  )
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

fn map_err(
  promise: Promise(Result(value, a)),
  map: fn(a) -> b,
) -> Promise(Result(value, b)) {
  promise |> promise.map(result.map_error(_, map))
}

// #################
// ### EXTERNALS ###
// #################

// For external use to prevent cyclical imports
pub fn new_could_not_get_storage_manager() -> Error {
  CouldNotGetStorageManager
}

pub fn new_could_not_get_root_directory(desc: String) -> Error {
  CouldNotGetRootDirectory(desc)
}

pub fn new_file_system_error(desc: String) -> Error {
  FileSystemError(desc)
}

type FsResult(a) =
  Promise(Result(a, Error))

type Handle(directory_or_file)

type DirectoryHandle =
  Handle(DirectoryT)

type FileHandle =
  Handle(FileT)

/// Phantom type marker for Handle, indicating a directory handle.
type DirectoryT

/// Phantom type marker for Handle, indicating a file handle.
type FileT

type File

@external(javascript, "./storage_ffi.js", "get_root_directory")
fn get_root_directory() -> FsResult(DirectoryHandle)

@external(javascript, "./storage_ffi.js", "all_entries")
fn all_entries(
  in directory: DirectoryHandle,
) -> FsResult(#(List(DirectoryHandle), List(FileHandle)))

@external(javascript, "./storage_ffi.js", "get_directory_handle")
fn get_directory_handle(
  in directory: DirectoryHandle,
  named name: String,
  create_if_missing create_if_missing: Bool,
) -> FsResult(DirectoryHandle)

@external(javascript, "./storage_ffi.js", "get_file_handle")
fn get_file_handle(
  in directory: DirectoryHandle,
  named name: String,
  create_if_missing create_if_missing: Bool,
) -> FsResult(FileHandle)

@external(javascript, "./storage_ffi.js", "remove_entry")
fn remove_entry(
  in directory: DirectoryHandle,
  named name: String,
  recursive recursive: Bool,
) -> FsResult(Nil)

@external(javascript, "./storage_ffi.js", "get_file")
fn get_file(handle: FileHandle) -> FsResult(File)

@external(javascript, "./storage_ffi.js", "file_text")
fn file_text(file: File) -> FsResult(String)

@external(javascript, "./storage_ffi.js", "write_file")
fn write(to file: FileHandle, write content: String) -> FsResult(Nil)
