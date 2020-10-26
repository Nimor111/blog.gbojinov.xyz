+++
title = "Peering into Scala optics with Monocle"
author = ["gbojinov"]
date = 2020-10-21T00:00:00+03:00
tags = ["scala", "optics", "fp"]
draft = true
summary = "An example of optics in Scala using the Monocle library."
+++

## Introduction {#introduction}

Salutations. Today i'm going to do an overview of one of my favourite functional programming concepts - optics. Most articles on this topic focus on Haskell so I'm going to try to present the topic using Scala and the [Monocle](https://github.com/optics-dev/monocle) library.


## Optics - The What and The Why {#optics-the-what-and-the-why}

Let's start with an example.
The examples of this post are taken from this fantastic page about optics: [Link](https://impurepics.com/posts/2020-03-22-optics.html)


### Initial steps {#initial-steps}

Let's define some types.

```scala
object Types {
  case class Name(value: String) extends AnyVal
  case class Stock(value: Int) extends AnyVal

  case class Bar(fridges: List[Fridge])
  case class Fridge(beers: List[Beer])
  case class Beer(name: Option[Name], stock: Option[Stock])
}
```

And here's what a `Bar` would look like sent over an API in a format like JSON:

```json
{
  "fridges": [{
    "beers": [
      {
        "name": "Starobrno",
        "stock": 5
      },
      {
        "stock": 2
      }
    ]
  },
  {
    "beers": [
      {
        "name": "Starobrno",
      },
      {
        "name": "Staropramen",
        "stock": 6
      }
    ]
  }]
}
```

Objects in the real world can look twice as nested as this, but it's a good place to start.


### Let's play around with our data {#let-s-play-around-with-our-data}

So we're imagining we're a bar and we store information about the beers we're selling and how many we have in stock. Of course, we keep them in a fridge, and our bar has multiple fridges. Not every beer has a name or a stock. (Let's hope the bar won't sell those without a name!)

Let's walk through a couple of use cases of what we would like to do with our beers.

-   We receive a shipment of beers for our first fridge and we would like to bump all of our stock by a certain amount. How would we do that?

Here's a way with regular (functional and immutable) Scala:

```scala
val beer1 = Beer(Some(Name("Starobrno")), Some(Stock(5)))
val beer2 = Beer(None, Some(Stock(3)))
val bar = Bar(List(Fridge(List(beer1, beer2))))

// Woo, a shipment comes!

val updatedBar = Bar(
  bar.fridges.map(fridge =>
    Fridge(fridge.beers.map(beer =>
      Beer(beer.name, beer.stock.map(s =>
        Stock(s.value + 1)))))))

println(updatedBar)
// Bar(List(Fridge(List(Beer(Some(Name(Starobrno)),Some(Stock(6))), Beer(None,Some(Stock(4)))))))
```

This works, but is less than ideal.

-   We would like to figure out how much stock we have in the first fridge of our bar.

<!--listend-->

```scala
bar.fridges.foldLeft(0)((total, fridge) =>
  total + fridge.beers.foldLeft(0)((fridgeTotal, beer) =>
    fridgeTotal + beer.stock.getOrElse(Stock(0)).value))

// 8
```

Again, less than ideal.

So, what can we do to make this code more concise and less convoluted?

Enter optics.


### Why do we care about optics? {#why-do-we-care-about-optics}

To be able to easily traverse deeply nested data structures (which is often the case with API responses) with minimal code and without lots of nested maps, folds, conditionals, etc. Optics make use of the compositional and pure nature of FP very well.

Optics are an abstraction characterized by several operations, which revolve around getting a particular field, setting it, or modifying it.

There are several types of optics.

`NB` Optics are called so because you "focus" into concrete elements of nested data structures with them, like the foci of a lens.


## Types of optics {#types-of-optics}

I will present four main types of optics: first with a little theory (the type definition and operations it supports), and then with an example with our data using the Monocle library.


### Lens {#lens}


#### Theory {#theory}

Lenses are used for getting and setting fields of deeply nested product types when you know the value is there.

The operations for lenses are:

1.  `get` (to get the value of the focused field),
2.  `set` (to change the value of the focused field)
3.  `modify` (to get an element and apply a function to it)

The SimpleLens type describes a structure `S` that contains a focused field of type `A`

```scala
abstract class SimpleLens[S, A] {
  def get(s: S): A
  def set(s: S, b: A): S
  def modify(s: S)(f: A => A): S = set(s, f(get(s)))
}
```

The type is actually a bit more complicated

```scala
abstract class Lens[S, T, A, B]

// so SimpleLens is
type SimpleLens[S, A] = Lens[S, S, A, A]
```

-   S - input structure type
-   T - output structure type, since setting the field can change the type (changing an int field to string for example)
-   A - input field type
-   B - output field type - again, might change

The `SimpleLens` is a convenient alias for when the input and output types are the same.

We create specific lenses for the fields we want to work with, e.g. we "focus" on the field.

To create a lens for the name field of the `Beer` type (let's ignore the `Option` there for now, we'll get to that later), we need a way to get a field from a case class and a way to set it. The minimal implementation for a Lens is to define `get` and `set` since `modify` can be expressed through them.

```scala
case class Name(value: String)
case class Beer(name: Name)

// We focus on the field with type Name of the Beer class
val beerName = new SimpleLens[Beer, Name] {
  def get(s: Beer): Name = s.name
  def set(s: Beer, newName: Name): Beer = s.copy(name = newName)
}

beerName.get(Beer(Name("Staropramen"))) // Name(Staropramen)
beerName.set(Beer(Name("Staropramen")), Name("Starobrno"))
beerName.modify(Beer(Name("Staropramen")))(n => Name(n.value + "!"))
```


#### In Practice {#in-practice}

The Monocle library provides convenient apply methods for creating a Lens by providing a get and set function. It also provides macros such as `GenLens` that avoid a lot of the boilerplate, but I'm not going to touch on them in this post.

```scala
import monocle.Lens

val barFridges = Lens[Bar, List[Fridge]](_.fridge)(newFridges => bar => bar.copy(fridges = newFridges))

val fridgeBeers = Lens[Fridge, List[Beer]](_.beers)(newBeers => fridge => fridge.copy(beers = newBeers))

// We'll get to the options soon
val beerStock = Lens[Beer, Stock](_.stock)(newStock => beer => beer.copy(stock = newStock))

val beerName = Lens[Beer, Name](_.name)(newName => beer => beer.copy(name = newName))

// Some examples
barFridges.get(bar)
fridgeBeers.set(fridge, List(beer1, beer2))
beerStock.modify(beer)(s => Stock(s.value + 5))
```


### Prism {#prism}


#### Theory {#theory}


#### In Practice {#in-practice}


### Traversal {#traversal}


#### Theory {#theory}


#### In Practice {#in-practice}


### Composability ( there was a table about this ) {#composability--there-was-a-table-about-this}


## Optics and Scala - Welcome to Monocle {#optics-and-scala-welcome-to-monocle}


### Example with Beers (can change this to accomodate StorePick domain me thinks) {#example-with-beers--can-change-this-to-accomodate-storepick-domain-me-thinks}


### Optics without operators {#optics-without-operators}


### Optics with operators {#optics-with-operators}


## Summary and Resources {#summary-and-resources}
