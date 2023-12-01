making noise with zig. stated goals:

- learning the basics of zig
- reimplementing the block diagram approach of [faust](https://faust.grame.fr/)
- having fun

# TODO

- [ ] change code to pass around pointers
- [ ] wavetable
  - initialize with a size and a generator function
  - generator function fills array from 0 to 1
  - interpolation function
- [ ] constructors should take !Block parameters and bubble up errors
