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

A lens is defined by:

1.  `get` (to get the value of the focused field),
2.  `set` (to change the value of the focused field)
3.  `modify` (to get an element and apply a function to  it) - this can be expressed through `get` and `set` so is not required

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

Prisms are used for getting and setting fields of deeply nested product types when the value might not be there. More generally, a prism captures a certain constructor of a sum type (since Option is simply a sum type with two constructors).

A nice way to think about prisms is that they define an is-a relationship and lenses define a has-a relationship.

A prism is defined by:

1.  `match` (a matcher function that returns an `Either` - Left if the constructor is matched, Right if it is)
2.  `construct` (a function to wrap a value into the constructor)

These operations are used to define some more convenient ones:

1.  `preview` (to get the value of the focused field, or None if it's not there) - this is analoguous to get, but returns an `Option`
2.  `review` (to wrap a value in the constructor)

The SimplePrism type describes a structure `S` that contains a focused field of type `A` that might not be there

```scala
abstract class SimplePrism[S, A] {
  def match(a: A): Either[S, A]
  def construct(a: A): S

  // the double match
  def preview(a: A): Option[A] = match this.match(a) {
    case Right(a) => Some(a)
    case Left(_) => None
  }

  def review(a: A): Option[A] = this.construct(a)
}
```

The type is actually a bit more complicated

```scala
abstract class Prism[S, T, A, B]

// so SimplePrism is
type SimplePrism[S, A] = Prism[S, S, A, A]
```

-   S - input structure type
-   T - output structure type, since setting the field can change the type (changing an int field to string for example)
-   A - input field type, a variant of a sum type
-   B - output field type - again, might change, a variant of a sum type

The `SimplePrism` is a convenient alias for when the input and output types are the same.

Let's create a prism for the Some constructor of the Option type, since we have several optional fields in our data.

```scala
// puns
val somePrism = new SimplePrism[Option[A], A] {
  def match(a: A): Either[Option[A], A] = a match {
    // the value is there
    case Some(y) => Right(y)
    // the value is missing
    case None => Left(None)
  }

  def construct(a: A): Option[A] = Some(a)
}

somePrism.preview(Some(5)) // Some(5))))
somePrism.review(5) // Some(5)
```

This isn't the most sensible example in of itself, but when we get to composing optics it'll be very convenient. In fact, it's so convenient that there is another type of optic, `Optional`, which composes a Lens and this prism to create Lenses for optional fields.


#### In Practice {#in-practice}

Since we will be using mainly the simple versions of the optics in our explorations (without changing the output types), we can use `Maybe` in our matching function instead of `Either`, which is there to keep the context of our switched `T` type.
Luckily, Monocle provides an apply method to supply a matching function with `Maybe` as the return type. What's more, it provides a `Prism.partial` constructor, which allows a partial function to be passed, making the code even more concise. Let's rewrite our prism for `Some` using Monocle.

```scala
import monocle.Prism

val prismOption[A]: Prism[Option[A], A] = Prism.partial[Option[A], A]{case Some(v) => v}(Some(_))
```

Neat, right?

Preview is called `getOption`, and review is `reverseGet`.

```scala
prismOption.getOption(Some(Name("Starobrno"))) // Some(Name(Starobrno))

prismOption.reverseGet(Name("Starobrno")) // Some(Name(Starobrno))
```

I promise, it'll make sense in a bit.


### Traversal {#traversal}


#### Theory {#theory}

Traversals are the meat and bread of traversing nested data, because they deal with lists of values. A traversal focuses on 0 or more values of a type, or a field that is a list of values of the same type. So a lens is actually a traversal that focuses on a single value.

A Traversal is basically a wrapper around types that can be traversed. `traverse` is like `map`, but the function that is applied to each element of the structure is effectful. A Traversal allows us to transform values of a field in any way we like.

A traversal is, not surprisingly, defined by the following function:

1.  `traverse` (apply an effectful function to each element of a structure)

This operation is used to define very many others, and implementing them will take longer than a reasonably sized blog post, so i'll just show their usage.

```scala
abstract class SimpleTraversal[S, A] {
  // traverse requires that the effect is an instance of Applicative
  def traverse[F[_]: Applicative](f: A => F[A])(s: S): F[S]
}
```

As always, the type can be more complicated.

```scala
abstract class Traversal[S, T, A, B]

type SimpleTraversal[S, A] = Traversal[S, S, A, A]
```

The type parameter explanation is the same as for the previous optics.

To implement a traversal, we can use the `Traverse` type class from cats (not to be confused with the default `Traversable` from Scala, though they sure meant us to confuse the two, since that is what `Traverse` is called in Haskell) and simply take its `traverse` method implementation.

```scala
// List[_] is an instance of ~Traverse~
val listTraverse[List[A], A] = new SimpleTraversal {
  def traverse[F[_]: Applicative](f: A => F[A])(s: List[A]): F[List[A]] = s.traverse(f) // assuming an extension method traverse is defined
}
```


#### In Practice {#in-practice}

We'll define traversals for our list of fridges and list of bars. Monocle provides a `Traversal.fromTraverse` constructor that does what we did above. It has a `Traverse` type class constraint.

```scala
import monocle.Traversal

val fridgeTraversal: Traversal[List[Fridge], Fridge] = Traversal.fromTraverse[List, Fridge]
val beersTraversal: Traversal[List[Beer], Beer] = Traversal.fromTraverse[List, Beer]
```

We can get all beers, which will make more sense when we compose the optics

```scala
val beer1 = Beer(Some(Name("Starobrno")), Some(Stock(4)))
val beer2 = Beer(None, Some(Stock(3)))

val beers = List(beer1, beer2)

beersTraversal.getAll(beers) // List(beer1, beer2)
```

For a more sensible example, we can fold them to calculate all the stock (using a monoid for Stock). I will cheat a bit here and use a compose, which I will cover in the next (culminative) section. Ignore it for now.

```scala
import monocle.Optional
import cats.Monoid

val beerStockOptional = Optional[Beer, Stock](_.stock)(newStock => beer => beer.copy(stock = Some(newStock)))

implicit val stockMonoid: Monoid[Stock] = new Monoid[Stock] {
  override def empty: Stock = Stock(0)
  override def combine(x: Stock, y: Stock): Stock = Stock(x.value + y.value)
}

beersL.composeOptional(beerStockOptional).fold(beers) // Stock(7)
```


## Composability {#composability}

There was a table about this


## Optics in full {#optics-in-full}


### Example with Beers (can change this to accomodate StorePick domain me thinks) {#example-with-beers--can-change-this-to-accomodate-storepick-domain-me-thinks}


### Optics without operators {#optics-without-operators}


### Optics with operators {#optics-with-operators}


## Summary and Resources {#summary-and-resources}
