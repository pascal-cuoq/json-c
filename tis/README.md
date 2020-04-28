Analysis of the [json-c](https://github.com/json-c/json-c) application
usong [TrustInSoft](https://trust-in-soft.com) tools.

The details of the steps can be found in [run.sh](./run.sh).



### Fixes


## Coverage

```
$ tis-analyzer -tis-config-load empty.config \
               -save empty.state -info-csv-all empty > empty.log
$ tis-aggregate coverage json-c.aggreg > json-c.coverage
```
