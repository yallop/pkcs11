v0.5.0 2016-12-16
=================

Breaking changes:

- `get_slot` return a result instead of raising an exception (#16)
- Make `P11.Mechanism.key_type` return an option (#17)

Cleanup:

- Fix warning 32 (#18)
- Fix warning 52 (#15)

Tests:

- Add tests for the bigint module (#14)

v0.4.0 2016-11-03
=================

Breaking changes:

- Changed the type of some low-level fields from `Ctypes.ptr` to
  `Ctypes_helpers.Reachable_ptr.t`. Those can be accessed using the `setf` and
  `getf` functions in the same module.
- Make `Pkcs11_data.t` abstract.

Fixes:

- Fix several use-after-free bugs (#10)

Build system:

- Add merlin configuration (#11)

v0.3.0 2016-10-18
=================

New features:

- Add inverted stubs (#8)

v0.2.0 2016-10-07
=================

Breaking changes:

- Rename `CK_PKCS5_PBKD2_DATA_PARAMS` to `CK_PKCS5_PBKD2_PARAMS` (#5)

New features:

- Install headers in ocamlfind directory (#2)

Changes:

- Improve documentation headers (#3)

v0.1.0 2016-09-22
=================

- Initial release.