# Carrier and APN data

The manual Profile form combines two public upstream datasets:

- Carrier identity, country, MCC, and MNC: `https://www.mcc-mnc.net/mcc-mnc.json`
  (MCC-MNC.net, MIT License).
- APN records: `device/sample/etc/apns-full-conf.xml` from the Android Open
  Source Project (Apache License 2.0).

ieSIM downloads both sources when the picker is first opened and stores the
last successfully parsed response in local preferences. If the network and
cache are both unavailable, a small built-in catalog keeps the form usable.

The selected MCC, MNC, and APN are suggestions, not device provisioning
instructions. Upstream records can lag carrier changes, so every populated
field remains editable before the Profile is saved.
