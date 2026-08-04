import gleam/dynamic/decode
import gleam/list
import gleam/result
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Tab(message) {
  Tab(id: String, name: String, contents: Element(message))
}

// Based on <https://www.w3.org/WAI/ARIA/apg/patterns/tabs/examples/tabs-automatic/>
// (2026-08-03)
/// All tabs must have unique ids.
pub fn tabs(
  tabs: List(Tab(message)),
  default_tab: String,
  selected_tab: Result(String, Nil),
  selected_message: fn(String) -> message,
) -> Element(message) {
  let first_tab = list.first(tabs)
  let last_tab = list.last(tabs)
  let #(buttons, panels) =
    tabs_loop(
      tabs:,
      buttons: list.new(),
      panels: list.new(),
      default_tab:,
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
  default_tab default_tab: String,
  selected_tab selected_tab: Result(String, Nil),
  selected_message selected_message: fn(String) -> message,
  prev_tab prev_tab: Result(Tab(message), Nil),
  first_tab first_tab: Result(Tab(message), Nil),
  last_tab last_tab: Result(Tab(message), Nil),
) {
  case tabs {
    [] -> #(list.reverse(buttons), list.reverse(panels))
    [tab, ..rest] -> {
      let next_tab = list.first(rest)

      let selected = tab.id == result.unwrap(selected_tab, or: default_tab)
      let button =
        html.button(
          [
            attribute.id("tab-" <> tab.id),
            attribute.role("tab"),
            attribute.aria_selected(selected),
            // Don't autofocus on initial page load
            attribute.autofocus(Ok(tab.id) == selected_tab),
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
        default_tab:,
        selected_tab:,
        selected_message:,
        prev_tab: Ok(tab),
        first_tab:,
        last_tab:,
      )
    }
  }
}
