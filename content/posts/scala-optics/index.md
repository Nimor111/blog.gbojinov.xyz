+++
title = "Peering into Scala optics with Monocle"
author = ["Georgi Bozhinov"]
date = 2020-10-21T00:00:00+03:00
tags = ["scala", "optics", "fp"]
draft = false
summary = "An example of optics in Scala using the Monocle library."
image = "images/diffraction.png"
+++

## Introduction {#introduction}

Salutations. Today i'm going to do an overview of one of my favourite functional programming concepts - optics. Most articles on this topic focus on Haskell so I'm going to try to present the topic using Scala and the [Monocle](https://github.com/optics-dev/monocle) library.

My assumptions for the reader is that they are familiar with basic functional Scala, the concept of type classes and some of the more popular ones.


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

```javascript
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

Objects in the real world can look quite a bit more nested than this, but it's a good place to start.


### Let's play around with our data {#let-s-play-around-with-our-data}

So we're imagining we're a bar and we store information about the beers we're selling and how many we have in stock. Of course, we keep them in a fridge, and our bar has multiple fridges. Not every beer has a name or a stock. (Maybe we brew our own type of beer!)

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

-   We would like to figure out how much stock we have in our bar.

    ```scala
        bar.fridges.foldLeft(0)((total, fridge) =>
          total + fridge.beers.foldLeft(0)((fridgeTotal, beer) =>
            fridgeTotal + beer.stock.getOrElse(Stock(0)).value))

        // 8
    ```

    Again, less than ideal.

So, what can we do to make this code more concise and less convoluted?

Enter optics.


### What do optics do and why should we care about them? {#what-do-optics-do-and-why-should-we-care-about-them}

To be able to easily traverse deeply nested data structures (which is often the case with API responses) with minimal code and without all these nested maps, folds, conditionals, etc. Optics make very good use of the compositional and pure nature of FP.

Optics are an abstraction characterized by several operations, which revolve around getting a particular field, setting it, or modifying it.

There are several types of optics.

`NB` Optics are called so because you "focus" into specific elements of nested data structures with them, like the foci of an optical device.


## Types of optics {#types-of-optics}

I will present three main types of optics: first with a little theory (the type definition and operations it supports), and then with an example with our data using the Monocle library.


### Lens {#lens}


#### Theory {#theory}

Lenses are used for getting and setting fields of deeply nested product types, when you know the value is there. (it's not optional)

A lens is defined by the following operations:

1.  `get` (to get the value of the focused field)
2.  `set` (to change the value of the focused field)
3.  `modify` (to get an element and apply a function to it) - this can be expressed through `get` and `set` so it's not required in an implementation

The `SimpleLens` describes a structure of type `S` that contains a focused field of type `A`

```scala
abstract class SimpleLens[S, A] {
  def get(s: S): A
  def set(s: S, b: A): S
  def modify(s: S)(f: A => A): S = set(s, f(get(s)))
}
```

The type is actually a bit more complicated

```scala
abstract class Lens[S, T, A, B] {
  def get(s: S): A
  def set(s: S, b: B): T
  def modify(s: S)(f: A => B): T = set(s, f(get(s)))
}

// so SimpleLens is
type SimpleLens[S, A] = Lens[S, S, A, A]
```

-   S - input structure type, our nested data structure
-   T - output structure type, since setting the field can change the type (changing an int field to a string for example)
-   A - input field type
-   B - output field type - again, the input type might change

The `SimpleLens` is a convenient alias for when the input and output types are the same.

We create specific lenses for the fields we want to work with, e.g. we "focus" on the field.

To create a lens for the name field of the `Beer` type (let's ignore the `Option` there for now, we'll get to that later), we need a way to get a field from a case class and a way to set it. The minimal implementation for a `Lens` is to define `get` and `set` since `modify` can be expressed through them.

```scala
case class Name(value: String)
case class Beer(name: Name)

// We focus on the field with type Name of the Beer class
val beerName = new SimpleLens[Beer, Name] {
  def get(s: Beer): Name = s.name
  def set(s: Beer, newName: Name): Beer = s.copy(name = newName)
}

beerName.get(Beer(Name("Staropramen"))) // Name(Staropramen)
beerName.set(Beer(Name("Staropramen")), Name("Starobrno")) // Beer(Name(Staropramen))
beerName.modify(Beer(Name("Staropramen")))(n => Name(n.value + "!")) // Beer(Name(Staropramen!))
```


#### In Practice {#in-practice}

The Monocle library provides convenient apply methods for creating a Lens by providing a get and set function. It also provides macros such as `GenLens` that avoid a lot of the boilerplate, but I'm not going to touch on them in this post.

```scala
import monocle.Lens

val barFridges = Lens[Bar, List[Fridge]](_.fridges)(newFridges => bar => bar.copy(fridges = newFridges))

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

1.  `match` (a matcher function that returns an `Either` - Left if the constructor is not matched, Right if it is)
2.  `construct` (a function to wrap a value into the constructor)

These operations are used to define some more convenient ones:

1.  `preview` (to get the value of the focused field, or None if it's not there) - this is analoguous to get, but returns an `Option`
2.  `review` (to wrap a value in the constructor)

The `SimplePrism` type describes a structure `S` that contains a focused field of type `A` that might not be there

```scala
abstract class SimplePrism[S, A] {
  // because reserved word
  def matcher(a: A): Either[S, A]
  def construct(a: A): S

  // the double match
  def preview(a: A): Option[A] = this.matcher(a) match {
    case Right(a) => Some(a)
    case Left(_) => None
  }

  def review(a: A): Option[A] = this.construct(a)
}
```

The type is actually a bit more complicated

```scala
abstract class Prism[S, T, A, B] {
  // we might choose a different type for our Left, some error for example
  def matcher(a: A): Either[T, A]
  // he we wrap whatever the result of our computation is back into the result sum type
  def construct(b: B): T

  def preview(a: A): Option[A] = this.matcher(a) match {
    case Right(a) => Some(a)
    case Left(_) => None
  }

  def review(b: B): T = this.construct(b)
}

// so SimplePrism is
type SimplePrism[S, A] = Prism[S, S, A, A]
```

-   S - input structure type
-   T - output structure type, since setting the field can change the type (changing an int field to string for example)
-   A - input field type, a variant of a sum type
-   B - output field type - again, might change, a variant of a sum type

The `SimplePrism` is a convenient alias for when the input and output types are the same.

Let's create a prism for the `Some` constructor of the `Option` type, since we have several optional fields in our data.

```scala
// puns
val somePrism = new SimplePrism[Option[A], A] {
  def matcher(a: A): Either[Option[A], A] = a match {
    // the value is there
    case Some(y) => Right(y)
    // the value is missing
    case None => Left(None)
  }

  def construct(a: A): Option[A] = Some(a)
}

somePrism.preview(Some(5)) // Some(5)
somePrism.review(5) // Some(5)
```

This isn't the most sensible example in of itself, but when we get to composing optics it'll be very convenient. In fact, it's so convenient that there is another type of optic, `Optional`, which composes a `Lens` and this prism to create lenses for optional fields.


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

Traversals are the meat and bread of traversing(get it?) nested data, because they deal with lists of values. A traversal focuses on 0 or more values of a type, or a field that is a list of values of the same type. So a lens is actually a traversal that focuses on a single value, and a prism is a traversal that focuses on on 0 or 1 value.

A Traversal is basically a wrapper around types that can be traversed. `traverse` is like `map`, but the function that is applied to each element of the structure is effectful. A `Traversal` allows us to transform values of a field in any way we like.

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
abstract class Traversal[S, T, A, B] {
  def traverse[F[_]: Applicative](f: A => F[B])(s: S): F[T]
}

type SimpleTraversal[S, A] = Traversal[S, S, A, A]
```

The type parameter explanation is the same as for the previous optics.

To implement a traversal, we can use the `Traverse` type class from cats (not to be confused with the default `Traversable` from Scala, though they sure meant us to confuse the two, since that is what `Traverse` is called in Haskell) and simply take its `traverse` method implementation.

```scala
// List[_] is an instance of ~Traverse~
val listTraversal[List[A], A] = new SimpleTraversal {
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

For a more sensible example, we can fold them to calculate all the stock (using a monoid for Stock). I will cheat a bit here and use a compose, which I will cover in the next (culminative) section.

```scala
import monocle.Optional
import cats.Monoid

// Composing a lens for Stock and a prism for Option yields an Optional
val beerStockOptional = Optional[Beer, Stock](_.stock)(newStock => beer => beer.copy(stock = Some(newStock)))
```

```scala
implicit val stockMonoid: Monoid[Stock] = new Monoid[Stock] {
  override def empty: Stock = Stock(0)
  override def combine(x: Stock, y: Stock): Stock = Stock(x.value + y.value)
}
```

```scala
// uses the Stock monoid
beersL.composeOptional(beerStockOptional).fold(beers) // Stock(7)
```


## Composability {#composability}

Now that we've looked at some of the main types of optics, it's time to see how they can be used with real data (or in our case, the data we defined at the beginning of the post). The power of optics lies in their ability to compose. By composing them we can perform the nested traversal that makes optics so useful.

Skipping over the theory, as that is a post on its own, the main thing to note is that, for the optics we presented, every one of them, composed with a `Traversal`, yields a `Traversal`. This means that a composed optic will most often be a `Traversal` and will begin with a `Traversal` of some kind, either for a specific field (since a `Lens` is a `Traversal`), followed by a list of something. Sound familiar?

I'm going to go straight to the Monocle examples for this.


## Optics in full {#optics-in-full}


### Optics for a bar {#optics-for-a-bar}

So we want to focus on the `Stock` of the beers in our bar, starting from the top. Let's see how that goes.

First we define the separate optics. Yet again, i'm not using the macros provided by Monocle.

Imports

```scala
import $ivy.`org.typelevel::cats-core:2.1.1`
import $ivy.`com.github.julien-truffaut::monocle-core:3.0.0-M4`
import $ivy.`com.github.julien-truffaut::monocle-macro:3.0.0-M4`
import monocle.{Lens, Traversal, Optional}
import Types._
import cats.implicits._
import cats.Monoid
```

A Lens for the "fridges" field

```scala
val barFridges: Lens[Bar, List[Fridge]] = Lens[Bar, List[Fridge]](_.fridges)(newFridges => bar => bar.copy(fridges = newFridges))
```

Now we need to Traverse the fridges

```scala
val fridgesL: Traversal[List[Fridge], Fridge] = Traversal.fromTraverse[List, Fridge]
```

A Lens for the "beers" field

```scala
val fridgeBeers: Lens[Fridge, List[Beer]] = Lens[Fridge, List[Beer]](_.beers)(newBeers => fridge => fridge.copy(beers = newBeers))
```

Now we need to Traverse the beers

```scala
val beersL: Traversal[List[Beer], Beer] = Traversal.fromTraverse[List, Beer]
```

An optional for the "stock" field, since it's optional

```scala
val beerStock: Optional[Beer, Stock] = Optional[Beer, Stock](_.stock)(newStock => beer => beer.copy(stock = Some(newStock)))
```

And now... we compose. The function names should be self explanatory.

```scala
val barStocks: Traversal[Bar, Stock] =
  barFridges.
    composeTraversal(fridgesL).
    composeLens(fridgeBeers).
    composeTraversal(beersL).
    composeOptional(beerStock)
```

And there we have it. Now, to test it out.

```scala
val firstFridgeBeer1 = Beer(Some(Name("Starobrno")), Some(Stock(5)))
val firstFridgeBeer2 = Beer(Some(Name("")), Some(Stock(2)))
val secondFridgeBeer1 = Beer(Some(Name("Starobrno")), None)
val secondFridgeBeer2 = Beer(Some(Name("Staropramen")), Some(Stock(6)))

val fridges = List(
  Fridge(List(firstFridgeBeer1, firstFridgeBeer2)),
  Fridge(List(secondFridgeBeer1, secondFridgeBeer2)))
val bar = Bar(fridges)
```

Get the total stock. We again require the `Stock` monoid implicit in scope.

```scala
implicit val stockMonoid: Monoid[Stock] = new Monoid[Stock] {
  override def empty: Stock = Stock(0)
  override def combine(x: Stock, y: Stock): Stock = Stock(x.value + y.value)
}

println(barStocks.fold(bar)) // Stock(13)
```

Bump all the stock.

```scala
println(barStocks.fold(barStocks.modify(s => Stock(s.value + 1))(bar))) // Stock(16)
```

I think that looks way better than the previous solutions.


### Operators {#operators}

Finally, since Haskell libraries enjoy using fancy operators so much (not to debate on their usefulness or anything), Monocle provides some of those as well:

```scala
val barStocksOperators: Traversal[Bar, Stock] =
  barFridges ^|->> fridgesL ^|-> fridgeBeers ^|->> beersL ^|-? beerStock
```

I'll leave the decision up to you whether to use them or not.


## Monocle 3 {#monocle-3}

`Disclaimer`: I will be using Monocle 3 with Scala 2 here, so many of the features of the Focus macro will not be
present. I'll probably do a separate blog post for Scala 3.

We used Monocle 2 throughout this post as the API it provides is good for explaining optics from the ground up
and seeing the different types and how they compose.
However, for production use, the recently released version 3 of Monocle made some pretty nice simplifications to
the API so that it's a lot easier to use without having to know all these fancy words.

The gist of it is that it introduces a `Focus` type class with a `focus` macro that represents a path in a
nested data structure. Depending on the type of field you apply it to, can figure out on its own whether to
generate a `Lens`, `Prism`, `Traversal`, and so on, so you don't have to do it yourself. Even though i'm a fan
of knowing how libraries and concepts work from the ground up, this definitely makes using the library as a
beginner a lot easier.

In line with `Focus`, all the `compose*` functions are being deprecated in favour of the `andThen` function,
which serves the same purpose - it can figure out on its own depending on what type of optics you apply to it,
what it needs to compose, and whether it can compose them at all.

So, the above lens for our bar would look like this in Monocle 3 (for Scala 2):

Imports

```scala
import monocle.macros.syntax.all._
import monocle.Focus
```

All stock

```scala
def barStocks(bar: Bar) = bar
  .focus(_.fridges).each
  .andThen(Focus[Fridge](_.beers)).each
  .andThen(Focus[Beer](_.stock)).some

println(barStocks(bar).foldMap(identity)) // sadly there doesn't seem to be a fold method here
```

Bump stock

```scala
val bumpedBar = barStocks(bar)
  .modify(s => Stock(s.value + 1))

println(barStocks(bumpedBar).foldMap(identity))
```


## Summary and Resources {#summary-and-resources}

I hope this journey through optics has been a useful and informative one for you. When used correctly, they can result in much cleaner and declarative code for accessing fields. Granted, you do need a bit of context, but that's the usual case. And they have fancy names!

Here are some resources if you want to learn more about optics. There are more types of optics that I didn't cover here, but they are usually some modification of the three presented.

1.  [The Monocle Documentation](https://www.optics.dev/Monocle/)
2.  [Repository with the examples for this post](https://github.com/Nimor111/optics-examples)
3.  [Haskell lens library](https://hackage.haskell.org/package/lens) - this is one of the most famous optics libraries, it's a bit advanced in its explanations though
4.  [Very nice optics pictures with explanations](https://impurepics.com/posts/2020-03-22-optics.html) - mentioned in this article
