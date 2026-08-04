import gleam/list
import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// Checkbox is left unimplemented because it's currently unneeded.
pub opaque type Item(message) {
  Button(label: String, on_click: Result(message, Nil), tabindex: Int)
  Submenu(
    label: String,
    items: List(Item(message)),
    open: Bool,
    on_change: Result(fn(Bool) -> message, Nil),
    tabindex: Int,
  )
  Radio(
    label: String,
    options: List(RadioItem(message)),
    on_select: fn(String) -> message,
  )

  Group(label: String, items: List(Item(message)))
  Separator
}

pub type RadioItem(message) {
  RadioItem(label: String, value: String, checked: Bool, disabled: Bool)
}

pub fn popup_menu(
  id: String,
  label: Element(message),
  button_attributes: List(Attribute(message)),
  open: Bool,
  items: List(Item(message)),
) -> Element(message) {
  // let items = case items {
  //   [] -> []
  //   [Button(..) as item, ..items] -> [Button(..item, tabindex: 0), ..items]
  //   [Submenu(..) as item, ..items] -> [Submenu(..item, tabindex: 0), ..items]
  //   [Radio(..) as item, ..items]
  //   | [Group(..) as item, ..items]
  //   | [Separator as item, ..items] -> [item, ..items]
  // }
  let items = list.map(items, item_elem)
  html.div([], [
    html.button(
      [
        attribute.id(id),
        attribute.aria_haspopup("true"),
        attribute.aria_expanded(open),
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
        attribute.classes([#("open", open)]),
      ],
      items,
    ),
  ])
}

pub fn button(
  label label: String,
  on_click on_click: Result(message, Nil),
) -> Item(message) {
  Button(label:, on_click:, tabindex: -1)
}

pub fn submenu(
  label label: String,
  items items: List(Item(message)),
  open open: Bool,
  on_change on_change: Result(fn(Bool) -> message, Nil),
) -> Item(message) {
  Submenu(label:, items:, open:, on_change:, tabindex: -1)
}

pub fn radio(
  label label: String,
  options options: List(RadioItem(message)),
  on_select on_select: fn(String) -> message,
) -> Item(message) {
  Radio(label:, options:, on_select:)
}

pub fn group(label: String, items: List(Item(message))) -> Item(message) {
  Group(label:, items:)
}

pub fn separator() -> Item(message) {
  Separator
}

fn item_elem(item: Item(message)) -> Element(message) {
  case item {
    Button(label:, on_click:, tabindex:) ->
      html.li([attribute.role("none")], [
        html.button(
          [
            attribute.role("menuitem"),
            attribute.tabindex(tabindex),
            conditional_on_click(on_click),
          ],
          [html.text(label)],
        ),
      ])
    Submenu(label:, items:, open:, on_change:, tabindex:) ->
      html.li([attribute.role("none")], [
        html.button(
          [
            attribute.role("menuitem"),
            attribute.tabindex(tabindex),
            attribute.aria_haspopup("true"),
            attribute.aria_expanded(open),
            conditional_on_click(case on_change {
              Ok(on_change) -> Ok(on_change(!open))
              Error(Nil) -> Error(Nil)
            }),
          ],
          [html.text(label)],
        ),
        html.menu(
          [attribute.role("menu"), attribute.aria_label(label)],
          list.map(items, item_elem),
        ),
      ])

    Radio(label:, options:, on_select:) ->
      html.li([attribute.role("none")], [
        html.ul(
          [attribute.role("group"), attribute.aria_label(label)],
          list.map(options, fn(radio_item) {
            let RadioItem(label:, value:, checked:, disabled:) = radio_item
            html.li(
              [
                attribute.role("menuitemradio"),
                attribute.aria_checked(case checked {
                  True -> "true"
                  False -> "false"
                }),
                attribute.aria_disabled(disabled),
                conditional_on_click(case disabled {
                  False -> Ok(on_select(value))
                  True -> Error(Nil)
                }),
              ],
              [html.text(label)],
            )
          }),
        ),
      ])
    Group(label:, items:) ->
      html.li([attribute.role("none")], [
        html.ul(
          [attribute.role("group"), attribute.aria_label(label)],
          list.map(items, item_elem),
        ),
      ])
    Separator -> html.li([attribute.role("separator")], [])
  }
}

fn conditional_on_click(message: Result(message, Nil)) -> Attribute(message) {
  case message {
    Ok(message) -> event.on_click(message)
    Error(Nil) -> attribute.aria_disabled(True)
  }
}
