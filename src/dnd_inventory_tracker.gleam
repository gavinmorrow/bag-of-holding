import dnd_inventory_tracker/storage.{type Storage}
import gleam/javascript/promise
import gleam/string
import lustre
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", #())

  Nil
}

type Model {
  Loading
  Loaded(storage: Storage)
  FailedToLoad(error: storage.Error)
}

type Message {
  StorageLoaded(storage: Storage)
  StorageFailedToLoad(error: storage.Error)
}

fn init(_args: #()) -> #(Model, Effect(Message)) {
  #(Loading, load_storage())
}

fn load_storage() -> Effect(Message) {
  effect.from(fn(dispatch) {
    promise.tap(storage.load(), fn(storage) {
      case storage {
        Ok(storage) -> dispatch(StorageLoaded(storage:))
        Error(error) -> dispatch(StorageFailedToLoad(error:))
      }
    })
    Nil
  })
}

fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    StorageLoaded(storage:) -> #(Loaded(storage:), effect.none())
    StorageFailedToLoad(error:) -> #(FailedToLoad(error:), effect.none())
  }
}

fn view(model: Model) -> Element(Message) {
  case model {
    Loading -> loading_view()
    Loaded(storage:) -> loaded_view(storage)
    FailedToLoad(error:) -> failed_to_load_view(error)
  }
}

fn loading_view() -> Element(Message) {
  html.p([], [html.text("Loading...")])
}

fn loaded_view(storage: Storage) -> Element(Message) {
  todo
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

  html.div([], [
    html.h2([], [html.text("Failed to load :(")]),
    html.p([], [html.text("Error: " <> error_message)]),
  ])
}
