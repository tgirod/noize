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

# Another approach

Maybe it is possible to have each block as a generic type, and build all the tree at compile time ? Would be nice.

Can you find out at compile time that the type T has a field `.input` and a method `.eval` ?
