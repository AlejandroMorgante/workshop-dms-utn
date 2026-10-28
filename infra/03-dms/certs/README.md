# Public RDS certificate bundle

`us-east-1-bundle.pem` was downloaded from the official RDS trust store:
https://truststore.pki.rds.amazonaws.com/us-east-1/us-east-1-bundle.pem

This is a public CA bundle, not a private key. DMS imports it to use PostgreSQL
`verify-full`. The stage is restricted to us-east-1. Refresh the bundle from the
same official source when RDS changes its certificate authorities.
