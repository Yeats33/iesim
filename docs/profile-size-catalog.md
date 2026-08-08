# Profile size catalog

ieSIM uses the public Profile Sizes dataset displayed by `euicc.info`:

```text
https://stats-backend.euicc.info/data/euicc_sizes.json
```

The catalog provides a reference Profile size and estimated installed sizes for
multiple EUM identifiers. These values describe the storage occupied by an
individual Profile; they do not describe the total storage capacity of an
eUICC chip or device.

The LPA import preview matches the SM-DP+ host locally, then displays the
reference size and the observed range across EUMs. ieSIM never sends the LPA
activation code or Matching ID to the catalog service.

The last successfully parsed response is cached locally and reused when the
source returns `304 Not Modified` or is temporarily unavailable. Displayed
values remain estimates because the installed size can vary with the target
eUICC/EUM and the exact Profile variant.
