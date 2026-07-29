import lustre
import lustre/element.{type Element}
import lustre/element/html

pub fn main() -> Nil {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

type Model {
  Model
}

type Message

fn init(_args) -> Model {
  Model
}

fn update(model: Model, message: Message) -> Model {
  model
}

fn view(model: Model) -> Element(Message) {
  let Model = model

  html.p([], [html.text("hello world!")])
}
