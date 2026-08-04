import gleam/dynamic/decode
import gleam/list
import gleam/result
import lustre/attribute.{type Attribute}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// Checkbox is left unimplemented because it's currently unneeded.
pub opaque type Item(id, value, message) {
  Button(label: String, id: id, on_click: Result(message, Nil))
  Submenu(
    label: String,
    id: id,
    items: List(Item(id, value, message)),
    open: Bool,
    on_change: Result(fn(Bool) -> message, Nil),
  )
  Radio(
    label: String,
    on_change: fn(value) -> message,
    options: List(RadioItem(id, value, message)),
  )

  Group(label: String, items: List(Item(id, value, message)))
  Separator
}

pub type RadioItem(id, value, message) {
  RadioItem(label: String, value: value, id: id, checked: Bool, disabled: Bool)
}

pub fn popup_menu(
  id: String,
  label: Element(message),
  button_attributes: List(Attribute(message)),
  selected: Result(id, Nil),
  on_select: fn(Result(id, Nil)) -> message,
  items: List(Item(id, value, message)),
) -> Element(message) {
  // let items = case items {
  //   [] -> []
  //   [Button(..) as item, ..items] -> [Button(..item, tabindex: 0), ..items]
  //   [Submenu(..) as item, ..items] -> [Submenu(..item, tabindex: 0), ..items]
  //   [Radio(..) as item, ..items]
  //   | [Group(..) as item, ..items]
  //   | [Separator as item, ..items] -> [item, ..items]
  // }
  let items =
    items_loop(
      items:,
      elems: list.new(),
      selected:,
      on_select:,
      prev_item: Error(Nil),
      first_item: first_id(in: items),
      last_item: last_id(in: items),
    )
  html.div([], [
    html.button(
      [
        attribute.id(id),
        attribute.aria_haspopup("true"),
        attribute.aria_expanded(result.is_ok(selected)),
        attribute.aria_controls(id <> "-menu"),
        ..button_attributes
      ],
      [label],
    ),
    html.menu(
      [
        attribute.id(id <> "-menu"),
        attribute.role("menu"),
        attribute.aria_labelledby(id),
        attribute.tabindex(-1),
        attribute.classes([#("open", result.is_ok(selected))]),
      ],
      items,
    ),
  ])
}

fn first_id(in items: List(Item(id, value, message))) -> Result(id, Nil) {
  list.find_map(items, fn(item) {
    case item {
      Button(id:, ..) | Submenu(id:, ..) -> Ok(id)
      Radio(options:, ..) ->
        list.first(options) |> result.map(fn(option) { option.id })
      Group(items:, ..) -> first_id(in: items)
      Separator -> Error(Nil)
    }
  })
}

fn last_id(in items: List(Item(id, value, message))) -> Result(id, Nil) {
  items
  |> list.reverse
  |> list.find_map(fn(item) {
    case item {
      Button(id:, ..) | Submenu(id:, ..) -> Ok(id)
      Radio(options:, ..) ->
        list.last(options) |> result.map(fn(option) { option.id })
      Group(items:, ..) -> last_id(in: items)
      Separator -> Error(Nil)
    }
  })
}

pub fn button(
  label label: String,
  id id: id,
  on_click on_click: Result(message, Nil),
) -> Item(id, value, message) {
  Button(label:, id:, on_click:)
}

pub fn submenu(
  label label: String,
  id id: id,
  items items: List(Item(id, value, message)),
  open open: Bool,
  on_change on_change: Result(fn(Bool) -> message, Nil),
) -> Item(id, value, message) {
  Submenu(label:, id:, items:, open:, on_change:)
}

pub fn radio(
  label label: String,
  on_change on_change: fn(value) -> message,
  options options: List(RadioItem(id, value, message)),
) -> Item(id, value, message) {
  Radio(label:, on_change:, options:)
}

pub fn group(
  label: String,
  items: List(Item(id, value, message)),
) -> Item(id, value, message) {
  Group(label:, items:)
}

pub fn separator() -> Item(id, value, message) {
  Separator
}

fn items_loop(
  items items: List(Item(id, value, message)),
  elems elems: List(Element(message)),
  selected selected: Result(id, Nil),
  on_select on_select: fn(Result(id, Nil)) -> message,
  prev_item prev_item: Result(id, Nil),
  first_item first_item: Result(id, Nil),
  last_item last_item: Result(id, Nil),
) -> List(Element(message)) {
  let keyboard_handler = fn(on_click, next_item) {
    keyboard_handler(
      on_select:,
      on_click:,
      prev_item:,
      next_item:,
      first_item:,
      last_item:,
    )
  }

  case items {
    [] -> list.reverse(elems)
    [item, ..items] ->
      case item {
        Button(label:, id:, on_click:) ->
          items_loop(
            items:,
            elems: [
              html.li([attribute.role("none")], [
                html.button(
                  [
                    attribute.role("menuitem"),
                    attribute.tabindex(-1),
                    attribute.autofocus(Ok(id) == selected),
                    conditional_on_click(on_click),
                    keyboard_handler(on_click, first_id(in: items)),
                  ],
                  [html.text(label)],
                ),
              ]),
              ..elems
            ],
            selected:,
            on_select:,
            prev_item: Ok(id),
            first_item:,
            last_item:,
          )
        Submenu(label:, id:, items: submenu_items, open:, on_change:) -> {
          let on_click = case on_change {
            Ok(on_change) -> Ok(on_change(!open))
            Error(Nil) -> Error(Nil)
          }
          items_loop(
            items:,
            elems: [
              html.li([attribute.role("none")], [
                html.button(
                  [
                    attribute.role("menuitem"),
                    attribute.tabindex(-1),
                    attribute.autofocus(Ok(id) == selected),
                    attribute.aria_haspopup("true"),
                    attribute.aria_expanded(open),
                    conditional_on_click(on_click),
                    keyboard_handler(on_click, first_id(in: items)),
                  ],
                  [html.text(label)],
                ),
                html.menu(
                  [attribute.role("menu"), attribute.aria_label(label)],
                  items_loop(
                    items: submenu_items,
                    elems: list.new(),
                    selected:,
                    on_select:,
                    prev_item: Error(Nil),
                    first_item: first_id(in: items),
                    last_item: last_id(in: items),
                  ),
                ),
              ]),
              ..elems
            ],
            selected:,
            on_select:,
            prev_item: Ok(id),
            first_item:,
            last_item:,
          )
        }
        Radio(label:, on_change: radio_on_change, options:) ->
          items_loop(
            items:,
            elems: [
              html.li([attribute.role("none")], [
                html.ul(
                  [attribute.role("group"), attribute.aria_label(label)],
                  list.map(options, fn(radio_item) {
                    let RadioItem(label:, value:, id:, checked:, disabled:) =
                      radio_item
                    {
                      let on_click = case disabled {
                        False -> Ok(radio_on_change(value))
                        True -> Error(Nil)
                      }
                      html.li(
                        [
                          attribute.role("menuitemradio"),
                          attribute.aria_checked(case checked {
                            True -> "true"
                            False -> "false"
                          }),
                          attribute.tabindex(-1),
                          attribute.autofocus(Ok(id) == selected),
                          attribute.aria_disabled(disabled),
                          conditional_on_click(on_click),
                          keyboard_handler(on_click, first_id(in: items)),
                        ],
                        [html.text(label)],
                      )
                    }
                  }),
                ),
              ]),
              ..elems
            ],
            selected:,
            on_select:,
            prev_item: list.first(options)
              |> result.map(fn(option) { option.id })
              |> result.or(prev_item),
            first_item:,
            last_item:,
          )
        Group(label:, items:) ->
          items_loop(
            items:,
            elems: [
              html.li([attribute.role("none")], [
                html.ul(
                  [attribute.role("group"), attribute.aria_label(label)],
                  items_loop(
                    items:,
                    elems: list.new(),
                    selected:,
                    on_select:,
                    prev_item: Error(Nil),
                    first_item: first_id(in: items),
                    last_item: last_id(in: items),
                  ),
                ),
              ]),
              ..elems
            ],
            selected:,
            on_select:,
            prev_item: first_id(in: items) |> result.or(prev_item),
            first_item:,
            last_item:,
          )
        Separator ->
          items_loop(
            items:,
            elems: [html.li([attribute.role("separator")], []), ..elems],
            selected:,
            on_select:,
            prev_item:,
            first_item:,
            last_item:,
          )
      }
  }
}

pub fn close(message: fn(Result(id, Nil)) -> message) -> Effect(message) {
  effect.from(fn(dispatch) { dispatch(message(Error(Nil))) })
}

fn keyboard_handler(
  on_select on_select: fn(Result(id, Nil)) -> message,
  on_click on_click: Result(message, Nil),
  prev_item prev_item: Result(id, Nil),
  next_item next_item: Result(id, Nil),
  first_item first_item: Result(id, Nil),
  last_item last_item: Result(id, Nil),
) -> Attribute(message) {
  event.advanced("keydown", {
    use key <- decode.field("key", decode.string)
    let item = case key {
      "ArrowUp" -> Ok(on_select(prev_item |> result.or(last_item)))
      "ArrowDown" -> Ok(on_select(next_item |> result.or(first_item)))
      "Home" -> Ok(on_select(first_item))
      "End" -> Ok(on_select(last_item))
      "Escape" -> Ok(on_select(Error(Nil)))
      "Enter" | "Space" -> on_click
      _ -> Error(Nil)
    }
    case item {
      Ok(item) ->
        decode.success(event.handler(
          dispatch: item,
          prevent_default: True,
          stop_propagation: True,
        ))
      Error(Nil) ->
        decode.failure(event.handler(on_select(Error(Nil)), False, False), "")
    }
  })
}

fn conditional_on_click(message: Result(message, Nil)) -> Attribute(message) {
  case message {
    Ok(message) -> event.on_click(message)
    Error(Nil) -> attribute.aria_disabled(True)
  }
}
