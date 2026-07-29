import gleam/bool
import gleam/dynamic/decode

pub type Inventory {
  Inventory(
    name: String,
    items: List(Item),
    weight_limit: Weight,
    coins_count_towards_weight_limit: Bool,
  )
}

const inventory_default = Inventory(
  name: "",
  items: [],
  weight_limit: Pounds(0),
  coins_count_towards_weight_limit: False,
)

pub fn inventory_decoder() -> decode.Decoder(Inventory) {
  use version <- decode.field("version", decode.string)
  use <- bool.guard(
    when: version != "1.0",
    return: decode.failure(inventory_default, "Inventory v1.0"),
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
    kind: ItemKind,
    cost: String,
    weight: Weight,
    description: String,
    stats: List(String),
  )
}

fn item_decoder() -> decode.Decoder(Item) {
  use name <- decode.field("name", decode.string)
  use category <- decode.field("category", decode.string)
  use kind <- decode.field("kind", item_kind_decoder())
  use cost <- decode.field("cost", decode.string)
  use weight <- decode.field("weight", weight_decoder())
  use description <- decode.field("description", decode.string)
  use stats <- decode.field("stats", decode.list(decode.string))

  Item(name:, category:, kind:, cost:, weight:, description:, stats:)
  |> decode.success
}

pub type ItemKind {
  Armor
  Coin
  Other
}

fn item_kind_decoder() -> decode.Decoder(ItemKind) {
  use variant <- decode.then(decode.string)
  case variant {
    "armor" -> decode.success(Armor)
    "coin" -> decode.success(Coin)
    "other" -> decode.success(Other)
    _ -> decode.failure(Other, "ItemKind")
  }
}

pub type Weight {
  Pounds(lbs: Int)
}

fn weight_decoder() -> decode.Decoder(Weight) {
  use lbs <- decode.field("lbs", decode.int)
  Pounds(lbs:) |> decode.success
}
