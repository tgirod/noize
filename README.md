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

- [ ] methods to generate mermaid flowchart code
- [ ] turn jack client into a backend type
  - take a Node type as parameter
  - adapt the number of inputs/outputs based on Node
  - auto-connect with hardware ports
- [ ] use liblo to expose OSC controls (use a node to define osc endpoint)
- [ ] node inputs added as optionnals to the constructor
  - if the value is set, input is replaced with constant value
- [ ] wavetable (PORT FROM PREVIOUS VERSION)
  - initialize with a size and a generator function
  - generator function fills array from 0 to 1
  - interpolation function
- [ ] turn the project back to a library rather than exe
- [ ] #someday parallelism : noize builds a tree of nodes - it would probably be possible to evaluate children in parallel.
- [ ] #someday SIMD : audio servers usually ask for a sampleframe, not a sample individually. Turning those sampleframes into vectors and using SIMD instructions to process them all at once could be interesting.
- [x] use ~libportaudio~ jack for audio
- [x] Par and Seq with more than two nodes
- [x] delay line
- [x] delay line with parametric length
- [x] buffer to read values
- [x] sinewave oscillator
- [x] sample rate (hardcoded)
- [x] add tests everywhere
  - how do I make sure the tests in noize.zig are run ?
- [x] more than one kind of data passing around nodes : it would make sense to pass around integers or booleans, maybe even optional types to represent event based transmissions
- [x] use comptime for the greater good
  - typechecking inputs and outputs ?
  - cool optimizations ?

# Fri Dec  8 22:17:47 CET 2023

There is something crazy cool to do with tuples.

1. define node's input and output as slices of types
2. generate corresponding tuple types with `std.meta.Tuple`
3. redefine eval as `eval(input: InputTuple, output: OutputTuple)`

And now I can pass tuples from one eval call to the next. It is also possible to concat tuples together, and if I need to split them, I can use `inline for` to iterate over.

Experiment is [here](./exp/tuple.zig), but this approach is so promising, integrating it in the main code is the next step.

# Sat Dec  9 20:26:46 CET 2023

The tuple experiment has been merged into the main codebase. Note that it raises a segfault at compile time with zig 0.11.0 but not with master.

# Wed Dec 13 09:14:43 CET 2023

Interfacing with C is not easy. I'm almost there with jack - registering a client, opening input and output ports, running a process callback - but the C API is leaking everywhere.

So in the end I'm writing jack bindings - but I guess someone already did the work ? I've just found https://machengine.org/pkg/mach-sysaudio/ and it looks like I could use that ...

# Thu Dec 14 07:10:22 CET 2023

It's alive! the jack backend is working!
