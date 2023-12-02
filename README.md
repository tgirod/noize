making noise with zig. stated goals:

- learning the basics of zig
- reimplementing the block diagram approach of [faust](https://faust.grame.fr/)
- having fun

# TODO

- [x] change code to pass around pointers
  - maybe blocks should be heap allocated
- [x] constructors should take !Block parameters and bubble up errors
- [ ] wavetable
  - initialize with a size and a generator function
  - generator function fills array from 0 to 1
  - interpolation function
- [ ] add tests everywhere
  - how do I make sure the tests in noize.zig are run ?
- [ ] turn the project back to a library rather than exe
