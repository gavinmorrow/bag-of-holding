import gleam/bool
import gleam/dynamic/decode
import gleam/json

pub type Inventory {
  Inventory(
    name: String,
    items: List(Item),
    weight_limit: Weight,
    coins_count_towards_weight_limit: Bool,
  )
}

pub const default = Inventory(
  name: "",
  items: [],
  weight_limit: Pounds(0),
  coins_count_towards_weight_limit: False,
)

pub fn to_json(inventory: Inventory) -> json.Json {
  let Inventory(name:, items:, weight_limit:, coins_count_towards_weight_limit:) =
    inventory

  json.object([
    #("version", json.string("1.0")),
    #("name", json.string(name)),
    #("items", json.array(items, item_to_json)),
    #("weight_limit", weight_to_json(weight_limit)),
    #(
      "coins_count_towards_weight_limit",
      json.bool(coins_count_towards_weight_limit),
    ),
  ])
}

pub fn decoder() -> decode.Decoder(Inventory) {
  use version <- decode.field("version", decode.string)
  use <- bool.guard(
    when: version != "1.0",
    return: decode.failure(default, "Inventory v1.0"),
  )

  use name <- decode.field("name", decode.string)
  use items <- decode.field("items", decode.list(item_decoder()))
  use weight_limit <- decode.field("weight_limit", weight_decoder())
  use coins_count_towards_weight_limit <- decode.field(
    "coins_count_towards_weight_limit",
    decode.bool,
  )

  Inventory(name:, items:, weight_limit:, coins_count_towards_weight_limit:)
  |> decode.success
}

pub type Item {
  Item(
    name: String,
    category: String,
    location: Location,
    cost: String,
    weight: Weight,
    description: String,
    stats: List(String),
  )
}

fn item_to_json(item: Item) -> json.Json {
  let Item(name:, category:, location:, cost:, weight:, description:, stats:) =
    item
  json.object([
    #("name", json.string(name)),
    #("category", json.string(category)),
    #("location", item_kind_to_json(location)),
    #("cost", json.string(cost)),
    #("weight", weight_to_json(weight)),
    #("description", json.string(description)),
    #("stats", json.array(stats, json.string)),
  ])
}

fn item_decoder() -> decode.Decoder(Item) {
  use name <- decode.field("name", decode.string)
  use category <- decode.field("category", decode.string)
  use location <- decode.field("kind", item_kind_decoder())
  use cost <- decode.field("cost", decode.string)
  use weight <- decode.field("weight", weight_decoder())
  use description <- decode.field("description", decode.string)
  use stats <- decode.field("stats", decode.list(decode.string))

  Item(name:, category:, location:, cost:, weight:, description:, stats:)
  |> decode.success
}

pub type Location {
  Body
  Backpack
  Pouch
}

fn item_kind_to_json(item_kind: Location) -> json.Json {
  case item_kind {
    Body -> json.string("body")
    Backpack -> json.string("backpack")
    Pouch -> json.string("pouch")
  }
}

fn item_kind_decoder() -> decode.Decoder(Location) {
  use variant <- decode.then(decode.string)
  case variant {
    "body" -> decode.success(Body)
    "backpack" -> decode.success(Backpack)
    "pouch" -> decode.success(Pouch)
    _ -> decode.failure(Backpack, "ItemKind")
  }
}

pub type Weight {
  Pounds(lbs: Int)
}

fn weight_to_json(weight: Weight) -> json.Json {
  let Pounds(lbs:) = weight
  json.object([
    #("lbs", json.int(lbs)),
  ])
}

fn weight_decoder() -> decode.Decoder(Weight) {
  use lbs <- decode.field("lbs", decode.int)
  Pounds(lbs:) |> decode.success
}
