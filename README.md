making noise with zig. stated goals:

- learning the basics of zig
- reimplementing the node diagram approach of [faust](https://faust.grame.fr/)
- having fun

# General approach

Noize is composed of nodes. Each node is defined by its inputs, outputs, internal state and eval function.

There are nodes defined for a variety of basic functions, and special nodes called operators.

Operators are used to combine nodes with each other, effectively connecting outputs to inputs in various ways. Inputs and outputs of the resulting nodes are derived from the combined nodes.

Evaluation is done by calling the eval function of the root node with an array storing inputs, and an array to store outputs.

All nodes are defined at compile time. Operators check at comptime that combined nodes are compatible, input/output wise. Also, no memory is allocated during runtime which is kind of cool.

Also, I guess it is possible to inline every eval function. I'm curious to see if there would be a performance gain.

# TODO

- [ ] Par and Seq with more than two nodes
- [ ] node inputs added as optionnals to the constructor
  - if the value is set, input is replaced with constant value
- [x] delay line
- [x] delay line with parametric length
- [x] buffer to read values
- [ ] wavetable (PORT FROM PREVIOUS VERSION)
  - initialize with a size and a generator function
  - generator function fills array from 0 to 1
  - interpolation function
- [x] sinewave oscillator
- [x] sample rate (hardcoded)
- [x] add tests everywhere
  - how do I make sure the tests in noize.zig are run ?
- [ ] turn the project back to a library rather than exe
- [x] more than one kind of data passing around nodes : it would make sense to pass around integers or booleans, maybe even optional types to represent event based transmissions
- [x] use comptime for the greater good
  - typechecking inputs and outputs ?
  - cool optimizations ?
- [ ] #someday parallelism : noize builds a tree of nodes - it would probably be possible to evaluate children in parallel.
- [ ] #someday SIMD : audio servers usually ask for a sampleframe, not a sample individually. Turning those sampleframes into vectors and using SIMD instructions to process them all at once could be interesting.

# ven. 08 déc. 2023 21:45:34 CET

There is something crazy cool to do with tuples.

1. define node's input and output as slices of types
2. generate corresponding tuple types with `std.meta.Tuple`
3. redefine eval as `eval(input: InputTuple, output: OutputTuple)`

And now I can pass tuples from one eval call to the next. To write the various operators, I just need a way to extract a subpart of a tuple as another one.

I'm pretty sure it is possible with some std.meta.fields shenanigans, but maybe there is another way ? Also, how is alignment working here ?

Anyway, experiment is [here](./exp/tuple.zig)
