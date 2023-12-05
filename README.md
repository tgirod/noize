making noise with zig. stated goals:

- learning the basics of zig
- reimplementing the block diagram approach of [faust](https://faust.grame.fr/)
- having fun

# TODO

- [x] change code to pass around pointers
  - maybe blocks should be heap allocated
- [x] constructors should take !Block parameters and bubble up errors
- [x] wavetable
  - initialize with a size and a generator function
  - generator function fills array from 0 to 1
  - interpolation function
- [ ] add tests everywhere
  - how do I make sure the tests in noize.zig are run ?
- [ ] turn the project back to a library rather than exe
- [ ] more than one kind of data passing around blocks : it would make sense to pass around integers or booleans, maybe even optional types to represent event based transmissions
- [ ] use comptime for the greater good
  - typechecking inputs and outputs ?
  - cool optimizations ?
- [ ] #someday parallelism : noize builds a tree of blocks - it would probably be possible to evaluate children in parallel.
- [ ] #someday SIMD : audio servers usually ask for a sampleframe, not a sample individually. Turning those sampleframes into vectors and using SIMD instructions to process them all at once could be interesting.

# NOTES

## heavy comptime approach

In exp/comptime.zig, I experimented with comptime to write the combinators. It is quite easy to pass two block types to Seq, and build custom input and output types based on those two blocks.

But it gets complicated when you start passing data around, because you need a lot of reflection to manipulate those generated structs.

## the middleground

Thanks to that experiment, I know have a new approach with comptime combinators and arrays of Kind to define inputs and inputs !
