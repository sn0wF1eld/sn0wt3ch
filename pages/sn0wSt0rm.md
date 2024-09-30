![Alt text](../resources/Sn0wSt0rm.png "Optional title")

Sn0wst0rm is built to process and "grind" data.
Receive data from anywhere, process it, and store it however and wherever you want.

# Usage

## Docker

Go to docker directory in sn0wst0rm project and execute:

```
./run-version.sh --version 1.0.0-alpha --gc Parallel --maxHeap 4G --minHeap 2G --config /path/to/config.edn --library /path/to/library.jar --env production 
```

## Direct jar execution

Go to the scripts folder and use:

```
./grind.sh --gc Parallel --maxHeap 4G --minHeap 2G --baseLibrary /path/to/sn0wst0rm/jar --config /path/to/config.edn --library /path/to/library.jar
```

If you want to debug the pipeline, use:

```
./grind-debug.sh --gc Parallel --maxHeap 4G --minHeap 2G --baseLibrary /path/to/sn0wst0rm/jar --config /path/to/config.edn --library /path/to/library.jar
```

## Summary

Sn0wst0rm uses .edn files as the main way to configure a pipeline.

A simple pipeline may be composed by 4 things:

- A source - part of the pipeline that retrieves the data to be processed;
- A grinder - responsible for processing the data and output the data in the format that is required
- An enricher - used to enrich processed or collected data with cached data from another source, this source
  might be a DB, a file, etc;
- A sink - responsible for outputting the processed data, be it a DB or a cloud platform, etc;
- A job - responsible for running at a specific scheduled point in time, and it can perform whatever it is needed
  out of it, like loading data from a database and outputting, refreshing cached data, etc.

It is not mandatory although, to have a grinder or an enricher, you can easily save the data from the source directly 
with a sink, if that is what is needed for that specific data source.

Sn0wst0rm has the concept of transactions (loosely used here), which means that every source, the moment they output a
value to be processed, it will be wrapped into a Transaction Shard, which will be held by a Transaction.
The shard will go through the pipeline and suffer all sorts of transformations, and when the sink is reached, depending
on the nature of the finished operation i.e. successful or not, the transaction will me marked as finished or failed.

The moment a transaction finishes, cleanup functions can be used to perform post processing with the resulting value.
Post processing can go from the default behaviour (logging the fact the transaction was successful/unsuccesful), or can
be whatever the developer wishes, like sending an email, or outputting a message to a AMQP queue, or even calling a
webservice.

## Before we start

It is important to note that this framework is meant for processing data in a clojure collection format, even though it can
in theory process Java objects and so on you need to be aware that:

- The objects that you will process need to implement the Serializable interface;
- If you don't use a clojure collection (vector, map, seq, etc) there are certain characteristics of the framework and
supporting software (St0rmWatch3r) that might not work properly. For instance, there's a capability to edit values of
failed transactions within the ui, before retrying the transaction, if the value is not a clojure collection, you will not
be able to do so.

### Transaction

Abstraction used to hold all related values being processed with the pipeline at that moment.

### Transaction Shard

The actual value being processed. Each transaction can contain multiple shards, the only way to have multiple shards in
a transaction, is to have a branched configuration, by this I mean a step is connected to more than one step, originating
a branching in the pipeline. This will act like a shard cloning, in the sense that we will have 2 different shards with
the same value being processed by multiple different steps. The only way for the transaction to end successfully is for
all the shards to be processed successfully without any issues.

## Configuration

```
{:api-server #profile {:default {:port 8183}
                       :local-docker {:port 8181}
                       :staging {:port 8181}
                       :production {:port 8181}}
 :system #profile {:default {:threads-type :virtual
                             :tx-manager {:type :mem
                                          :conf {:tx-file "/Users/iceman/Desktop/transactions.edn"}}
                             :global-state-manager {:type :mem
                                                    :state {:http-root "https://demo.t-scape.com"
                                                            :pull-positions-schedule "0 0 0 * * * *"
                                                            :import-securities-schedule "10 0 0 * * * *"
                                                            :import-parties-schedule "15 0 0 * * * *"
                                                            :reminder-email-schedule "30 0 0 1-5 * * *"
                                                            :validation-priority-schedule "0 0 1 * * * *"
                                                            :rabbitmq-host "10.10.10.208"
                                                            :rabbitmq-host-port 5672
                                                            :job-on-output {:topic "admin.job-execution.logs"
                                                                            :exchange "admin.exchange"
                                                                            :message-conf {}
                                                                            :q-conf {:durable true
                                                                                     :auto-delete false}}
                                                            :event-creation-on-output {:topic "admin.job-execution.logs"
                                                                                       :exchange "admin.exchange"
                                                                                       :message-conf {}
                                                                                       :q-conf {:durable true
                                                                                                :auto-delete false}}
                                                            :datomic-db-name "iacts-vote-manager"
                                                            :datomic-db-cfg {:server-type :peer-server
                                                                             :access-key :env/datomic-access-key
                                                                             :secret :env/datomic-secret
                                                                             :endpoint "idk"
                                                                             :validate-hostnames false}
                                                            :blob-storage-type :postgres
                                                            :blob-storage-uri "postgresql://postgres:postgres@172.31.16.216:5432/blobs"}
                                                    :conf {}}}}
 :pipelines [{:name "pipeline1"
              :synchronized? true
              :jobs [{:name "generate-number-job"
                      :tx {:fail-fast? false
                           :retries 0}
                      :schedule "/50 * * * * * *"
                      :connects-to ["number-increaser"]
                      :fns {:x-fn (fn [_ _] (rand-int 100))}}]
              :sources [{:name "number-generator"
                         :tx {:fail-fast? true
                              :retries 0}
                         :fns {:x-fn (fn [_ _] (rand-int 100))}
                         :poll-frequency 1
                         :time-unit "m"
                         :threads 1
                         :connects-to ["number-increaser"]}]
              :grinders [{:name "number-increaser"
                          :tx {:fail-fast? false
                               :retries 0}
                          :fns {:x-fn (fn [_ _ value]
                                        (if (= 0 (rem value 2))
                                          (inc value)
                                          (throw (ex-info "Fictitious problem found" {}))))}
                          :poll-frequency 50
                          :time-unit "ms"
                          :threads 1
                          :connects-to ["number-logger"]}]
              :sinks [{:name "number-logger"
                       :tx {:fail-fast? false
                            :retries 0}
                       :fns {:x-fn (fn [_ _ value]
                                     (clojure.tools.logging/info "Number logged:" value))}
                       :timeout 1000
                       :poll-frequency 500
                       :time-unit "ms"
                       :threads 1}]}
             {:name "pipeline2"
              :jobs [{:name "generate-number-job2"
                      :tx {:fail-fast? false
                           :retries 0}
                      :schedule "/45 * * * * * *"
                      :connects-to ["number-increaser2"]
                      :fns {:x-fn (fn [_ _] (rand-int 100))}}]
              :sources [{:name "number-generator2"
                         :tx {:fail-fast? true
                              :retries 0}
                         :fns {:x-fn (fn [_ _] (rand-int 100))}
                         :poll-frequency 45
                         :time-unit "s"
                         :threads 1
                         :connects-to ["number-increaser2"]}]
              :grinders [{:name "number-increaser2"
                          :tx {:fail-fast? false
                               :retries 0}
                          :fns {:x-fn (fn [_ _ value]
                                        (if (= 0 (rem value 2))
                                          (inc value)
                                          (throw (ex-info "Fictitious problem found" {}))))}
                          :poll-frequency 50
                          :time-unit "ms"
                          :threads 1
                          :connects-to ["number-logger2"]}]
              :sinks [{:name "number-logger2"
                       :tx {:fail-fast? false
                            :retries 0}
                       :fns {:x-fn (fn [_ _ value]
                                     (clojure.tools.logging/info "Number logged:" value))}
                       :timeout 1000
                       :poll-frequency 500
                       :time-unit "ms"
                       :threads 1}]}]
 :error-sink {:poll-frequency 500
              :time-unit "ms"
              :threads 1}}
```

The current version of sn0wst0rm, contains 3 main configuration points:

- API Server;
- System;
- Pipelines;

## API Server

The api server contains all the information for the API part of sn0wst0rm.
This provides the user information about how many errors have occurred on specific steps,
or a general view of the entire pipeline.

Its configuration for the moment, is composed only of the port where the server is going to be running.

## System

The system key contains the 'system' configuration i.e. the instance's configuration for multiple environments.
It contains 3 different topics:

- Threads Type - Since Sn0wSt0rm was updated to use JDK21, Virtual threads were added, and to use them in the thread pools
that the framework uses, you just need to set the `:threads-type` to `:virtual`.
If you want to use platform threads, then set it to `:platform`.
By default platform threads are used.

- Tx Manager - The tx-manager configuration is mandatory, although, if there isn't a tx-manager that is properly configured, it will
try to default to in-memory managed type (:mem).

The configuration that needs to be added to the steps configuration looks like the following:

```
:tx-manager {:type :mem
             :conf {:tx-file "/Users/iceman/Desktop/transactions.edn"}}
```

It contains the following:

`:type` - the type of manager to be used (currently only :mem is supported);
`:conf` - contains the specific configuration for the transaction manager (in the case of the :mem type, we need a file
location).

When the transaction manager was introduced, it was done so to enable the serialization of current operations, i.e. to
make sure that the `in-flight` data is not lost. To do so, we need to serialize the in-flight objects and flush them to
disk, and, if present, load them back from disk, and continue processing when the service is restarted. 
For the :mem tx-manager, this translates to having a `:file` configuration, to know exactly where to save/load that data from. 
This might eventually be replaced with CRAC, which allows to snapshot a JVM execution state, removing the need for serialization.

### Global State Manager

The global state manager, as the name indicates is a way to handle data that needs to be shared across multiple
steps/pipelines.
This should only be used in extreme cases, where there's actually the need to do so.

Same as the tx-manager, it too only takes two configuration arguments:

```
:global-state-manager {:type :mem
                       :conf {}
                       :state {}}
```

`:type` - the type of manager to be used (currently only :mem is supported);
`:conf` - contains the specific configuration for the transaction manager;
`:state` - contains all current state, which means common configurations can be added once and shared across multiple
steps.

This concept is really useful, since it means you don't need to repeat the config anywhere. Let's say you want to
configure
the db details for a JDBC connection once, and then use it in multiple places, this is what you would do in the
global-state-manager:

```
...
:global-state-manager {:type :mem
                       :conf {}
                       :state {:db-cfg {:db-type "postgres"
                                        :db-name "test"}}}
...                                                           
```

Then, to use this global config in a step, you would do something like this in the step config:

```
...
:db-cfg :global/db-cfg
...
```

Notice the `:global` prefix of the keyword, this lets the framework initializer know that the config it needs on that
specific
step is present in the global state.

We also provide a way to resolve environment variables, basically instead of using the prefix `:global`
you use the prefix `:env`.

You can also mix and match both of them, what I mean by this is, you can refer to a global configuration within a step,
and in turn a global config can refer to an environment variable. Let's say you want to configure a db connection once
again, but you want to keep the password to the connection safe in a environment variable, you would do the following:

```
...
:global-state-manager {:type :mem
                       :conf {}
                       :state {:db-cfg {:db-type "postgres"
                                        :db-name "test"
                                        :db-password :env/db-password}}}
...                                                           
```

And on the step config:

```
...
:db-cfg :global/db-cfg
...
```

This would make the initializer look for the `db-cfg` in the global state, and then for the `db-password` in the
environment variable `DB_PASSWORD`.

## Pipelines

Pipelines contain all the pipelines that are ran within the current instance, they have single configuration, so they
are not different per environment. 
Although, since you can use the global state to specify the configuration, then there's no need for different pipelines
entries per environment, lowering the size of the configuration file.

### Synchronized?

Sn0wst0rm uses transactions, as explained above, but the regular way of handling multiple sourced values, is to process
them as they come, which means that at any time, you might have multiple transactions being processed at the same time. 
With this in mind, there might be some situations where we want the value to be processed completely until the end, 
before we actually start to process another value.
For this we have the keyword `:synchronized?`, which can be set to `false` or `true`. If set to true, then the behaviour
explained previously will be observed, where each transaction will complete before the next is attempted. 
If set to `false` or not present, a transaction will be created the moment a new value is sourced.

NOTE: Each step can be configured with a certain amount of threads, that means that we can still process multiple
transactions in parallel, but that thread won't be freed, until the transaction is completely finished (either successfully or not).

### Steps

The steps contain everything related to the pipeline, i.e. everything from the pipes (queues) to the steps themselves.
As mentioned above, there are multiple types of steps that can be used in the configuration. These need to be added to
the respective vector inside the configuration. Therefor we will end up with:

`:sources []` - for all the sources used in the pipeline;

`:grinders []` - for all the grinders used in the pipeline;

`:enrichers []` - for all the enrichers used in the pipeline;

`:sinks []` - for all the sinks used in the pipeline;

`:jobs []` - for all the jobs used in the pipeline;

each type has common arguments with all other steps, as well as custom ones, that are only used in that specific step.

NOTE: Splitters and demuxi were removed, and are now basically merged into every step. In order to split a value, an
extra key needs to be added to the step conf called `:step-conf` like so:

```
...
:split-conf {:group-size 50}
...
```

This will split the collection present in the value into chunks of 50.

### Tx

In this scope, a transaction is a set of operations that need to happen successfully, for an operation to be classified
as successful. The tx configuration usually can look like this:

```
:tx {:fail-fast? false
     :retries 5}
```

Each tx can have the following keys in its config:

- `:fail-fast?` - this is the flag that decides if an exception was to occur, would we stop the entire processing
  pipeline
  or not. For instance, if the entire system is dependent on a database, maybe it is better to gracefully stop it, than
  to risk losing data.
- `:retries` - this is used to set the number of retries we want to happen if something fails. If the step in question
  is dependent on an external system, and it fails the processing of the data, we might want to retry an x amount of
  times
  before we actually give up and execute the cleanup function.

### Queue conf

Depending on the processing type, the queues can have different configurations. If local, then the only configuration
possible is the buffer size:

```
:queue-conf {:buffer-size 10}
```
The buffer size sets the default size of that queue, from which it can only be changed by changing the config, or by using
St0rmwatch3r to do it while the instance is being executed.

## Steps Configuration

With this latest iteration of the framework (v 0.9.9+), it was decided to simplify the configuration process.
Now we have a base configuration that can be used by every step, and it looks like the following:

```
{:name "tweet-importer"
 :await-termination-time 2000
 :editable true
 :batch-size 100
 :tx {:fail-fast? false
      :retries 2}
 :connects-to ["tweet-interpreter"]
 :forwards-to ["some-other-pipeline"]
 :split-conf {:group-size 50}
 :conf {:some-key "some-value"}
 :error-conf {:some-conf "value"}
 :fns {:x-fn twitter-hashtag-counter.core/get-data
       :clean-up-fn (fn [a b] (clojure.tools.logging/info "Transaction cleaned!"))
       :v-fn (fn [v])
       :sw-fn (fn [this shard])
       :error-fn (fn [this conf error])}
 :keep-meta true
 :type sn0wst0rm-core.protocols.impl/map->DatomicSink
 :poll-frequency 500
 :time-unit "us"
 :threads 1}
```

- `:name` - the name of the step;
- `:await-termination-time` - when stopping the system, this is the time (ms) the step executor will wait for all tasks
  to finish, if this value is not provided, it will default to 1000 (ms).
- `:editable` - whether the value that has failed to be processed by this step, is or not editable from the UI (defaults
  to false);
- `:batch-size` - batch processing is now enabled in the system, set this value to a specific number to set the batch
  size. If no key added, will make the system default to single value processing;
- `split-conf` - contains configuration for the case where the value outputted is a vector. This contains the size of
  the group to generate, `:group-size`. Each segment will create a shard within the same transaction;
- `splitted?` - this flag is used in the case the result of the source function returns a collection. If set to true,
  the collection will get split into single values, and each value will generate a single transaction.
  Different from setting the split-conf group-size to 1, which would split the transaction into multiple shards
  Only available in Sources and Jobs;
- `tx` - the transactional configuration, it contains the following:
    - `:fail-fast?` - whether the system should be shutdown if an exception is detected while executing this step's
      function.
    - `:retries` - the number of times a failure should be retried before continuing on to the next execution.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:forwards-to` - this specifies a vector of steps where the value can be forwarded after the last step in the
  pipeline.
  This allows the developer to route data through various pipelines, making it possible, to keep transforming
  the value further even after it was saved at the end of the last pipeline, effectively creating checkpoints
  for values if you will. The step names used, need to be of a specific source type `Sn0wSt0rmQueueSource`;
- `conf` - the configuration map used by the `x-fn`;
- `error-conf` - the configuration map used by the error function. Optional as you might not be interested to do
  anything with the error itself besides having it logged to the file;
- `:fns` - a map containing keys as function names and values as either function code, or function path. Like so:

  ```
  :fns {:x-fn twitter-hashtag-counter.core/get-data
      :v-fn (fn [conf])
      :sw-fn (fn [this value])
      :error-fn (fn [thread pipeline-id tx-id tx-shard-id conf error value])
      :forward-fn (fn [this value conf])
      :clean-up-fn (fn [successful? value])}
  ```

  In the case above, we have a transformation function that was declared somewhere else (`:x-fn`), a validation function
  that is declared directly in the config (`:v-fn`) and a switching function (`:sw-fn`) that decides where the output is
  directed depending on the value, and finally `error-fn` which, in conjunction with `error-conf` is used to treat the
  error
  generated by the step, and do with it whatever the programmer wants to, like sending it to a queue, printing it in the
  console,
  etc.

  These functions have specific arities, and need to be configured accordingly:
  - `:x-fn` - this is always mandatory on generic steps (might not be in pre implemented ones), but the arity will
  depend on
  the type of step it is being configured for, so check each one to make sure you are configuring it correctly;
  - `:v-fn` - optional function, used to validate the configuration (conf) of the step. Takes a single argument, the
  step config.
  Will return true by default if not provided, validating the configuration and letting the step run.
  - `:sw-fn` - optional function, used to act as a switch, i.e. route the processed value depending on the result to
  different channels. Takes 2 arguments `[this value]`.
  - `:error-fn` - optional function, used to treat an error generated by the step. Takes 3 arguments `[this conf error]`.
  - `:forward-fn` - optional function, used to decide on where the sinked value should be forwarded next. Only supported
  by sinks.
  Outputs the name or names of steps where to send the value next. Takes 3 arguments, `this` , `value` and `conf`.
  - `:clean-up-fn` - optional function, used to be ran after the transaction is finished to perform post processing. 
  Takes 2 arguments `[successful? value]`. `successful` is the final state of the transaction, and the value is a map like:

      ```
      {:tx-id tx-id
       :tx-shard-id id
       :value value
       :conf conf
       :throw throw}
      ```
      
      - `:tx-id` - the id of the finished transaction;
      - `:tx-shard-id` - the id of the shard that reached the end of the pipeline;
      - `:value` - the value processed by that specific step;
      - `:conf` - the configuration of the step;
      - `:throw` - in case the transaction ended in an error, `throw` will contain the actual exception. 
      This can be used to customize different cleanup behaviours per exception type.

- `:keep-meta` - flag that sets the behaviour regarding metadata. If set to true, the metadata will be kept in the
  processed value, otherwise it will be removed;
- `:type` - this is used in case we have a predefined source type (an external library for instance) that was previously
  implemented. If this is not present, then it will try to check if a custom function(x-fn) is present to use as a
  source;
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);

## Sources Configuration

Each generic source has the following arguments:

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
- `:error-conf` - the configuration map used by the error function. Optional as you might not be interested to do
  anything with the error itself besides having it logged to the file;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - this is used in case we have a predefined source type (an external library for instance) that was previously
  implemented. If this is not present, then it will try to check if a custom function(x-fn) is present to use as a
  source;
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:splitted?` - whether the collection/vector of the result should be splitted into single values/transactions, `false`
  by default;
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
    - `:fns` - as explained above, needs to be a map of key/function. The source, particularly needs `:x-fn`.
      - `:x-fn` - mandatory, has arity of 2 `[thread-number conf]`. All other functions can be used, with the exception
      of
      `:forward-fn` which can only be used by sinks.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `:keep-meta` - whether the metadata should be kept on the processed value;
- `:editable` - St0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

## Jobs Configuration

Each job has the following arguments

- `:name` - the name of the step;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `splitted?` - whether the collection/vector of the result should be splitted into single values/transactions;
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:fns` - as explained above, needs to be a map of key/function. The source, particularly needs `:x-fn`.
    - `:x-fn` - mandatory, has arity of 2 `[thread-number conf]`. All other functions can be used, with the exception of
      `:forward-fn` which can only be used by sinks.
- `:schedule` - a cron like string responsible for creating the execution behaviour of the job.

## Grinders Configuration

Each generic Grinder has the following arguments

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
- `:error-conf` - the configuration map used by the error function. Optional as you might not be interested to do
  anything with the error itself besides having it logged to the file;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - this is used in case we have a predefined source type (an external library for instance) that was previously
  implemented. If this is not present, then it will try to check if a custom function(x-fn) is present to use as a
  source;
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - as explained above, needs to be a map of key/function. The grinder, particularly needs `:x-fn`.
    - `:x-fn` - mandatory, has arity of 2 `[thread-number conf value]`. All other functions can be used, with the
      exception of
      `:forward-fn` which can only be used by sinks.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `:keep-meta` - whether the metadata should be kept on the processed value;
- `:editable` - St0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

## Enrichers Configuration

Each generic Enricher has the following arguments

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
- `:error-conf` - the configuration map used by the error function. Optional as you might not be interested to do
  anything with the error itself besides having it logged to the file;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - this is used in case we have a predefined source type (an external library for instance) that was previously
  implemented. If this is not present, then it will try to check if a custom function(x-fn) is present to use as a
  source;
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:cache-poll-frequency` - the pool frequency in milliseconds at which the cache is refreshed. Needs `:cache-time-unit`
- `:cache-time-unit` - the time unit to be used by the cache (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - as explained above, needs to be a map of key/function. The source, particularly needs `:x-fn` and `c-fn`.
    - `:x-fn` - mandatory, has arity of 2 `[thread-number conf value cache]`. This function is responsible for mixing
      the value with the cache.
    - `c-fn` - mandatory, has arity of 1 `[conf]`. This function is responsible for updating the cached value, that will
      be used
      to enrich the value received.
    - All other functions can be used, with the exception of`:forward-fn` which can only be used by sinks.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `:keep-meta` - whether the metadata should be kept on the processed value;
- `:editable` - St0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

## Sinks Configuration

Each generic Sink has the following arguments

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
- `:error-conf` - the configuration map used by the error function. Optional as you might not be interested to do
  anything with the error itself besides having it logged to the file;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - this is used in case we have a predefined source type (an external library for instance) that was previously
  implemented. If this is not present, then it will try to check if a custom function(x-fn) is present to use as a
  source;
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - as explained above, needs to be a map of key/function. The source, particularly needs `:x-fn`.
    - `:x-fn` - mandatory, has arity of 2 `[thread-number conf value]`. This function is responsible for sinking the value.
    - All other functions can be used, even `:forward-fn` which can only be used by sinks.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `:keep-meta` - whether the metadata should be kept on the processed value;
- `:editable` - St0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

# Configuration by steps type

Above we can see all available configurations for the generic types, although `sn0wst0rm` contains specific types, that
are pre implemented and allow developers to just use them instead of creating a new one every time they need to
implement a
new case.

## Pre implemented sources

### Sn0wSt0rmQueueSource

This source is only used to have an anchor for forwarded values. What this means is, if you want to forward a value from 
a sink on another pipeline to the beginning of another pipeline, you need to add one of these sources to the target pipeline.

- `:name` - the name of the step;
- `:error-conf` - the configuration map used by the error function. Optional as you might not be interested to do
  anything with the error itself besides having it logged to the file;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - set to `sn0wst0rm-core.protocols.protocols.Sn0wSt0rmQueueSource`
- `:fns` - as explained above, needs to be a map of key/function. Does not have an `x-fn`.
  - All other functions can be used, besides `:forward-fn` which can only be used by sinks.
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `:keep-meta` - whether the metadata should be kept on the processed value;
- `:editable` - St0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

### FileWatcherCustomSource

This source is used to watch a specific directory, and load all files that are place in the folder into the designed
pipeline.

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
- `:error-conf` - the configuration map used by the error function. Optional as you might not be interested to do
  anything with the error itself besides having it logged to the file;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - set to `sn0wst0rm-core.protocols.protocols.FileWatcherCustomSource`
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - as explained above, needs to be a map of key/function. The source, particularly needs `:file-filter-fn`.
  - `:file-filter-fn` - takes 1 argument `[value]`, and is used to filter the sourced files to get only the ones that need
  processing.
  - All other functions can be used, besides `:forward-fn` which can only be used by sinks. 
- `:file-batch-size` - the max number of files read everytime the source runs;
- `:watch-dir` - configures the directory to watch.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `:keep-meta` - whether the metadata should be kept on the processed value;
- `:editable` - St0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

### DatomicSource

This source is used to retrieve data from a datomic database periodically, by executing the same query every time.

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
- `:error-conf` - the configuration map used by the error function. Optional as you might not be interested to do
  anything with the error itself besides having it logged to the file;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - set to `sn0wst0rm-core.protocols.protocols.DatomicSource`
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - as explained above, needs to be a map of key/function. Does not have an `x-fn`.
The source, particularly needs `q-fn`.
  - `:q-fn` - takes 2 arguments `[conn query-args]`, `conn` - the datomic connection, `query-args` - the arguments needed 
  for the query to run properly (vector).
  - All other functions can be used, besides `:forward-fn` which can only be used by sinks.
- `:query-args` - a vector that contains all the arguments necessary to the query execution.
- `:db-name` - contains the name of the db we are trying to connect to.
- `:timeout` - a long value with the amount of time the connector will wait to establish a successful datomic
  connection.
- `:db-cfg` - a map that contains the necessary elements to establish a datomic connection, like:

```
  {:server-type :peer-server
   :access-key :env
   :secret :env
   :endpoint "sn0wf1eld.com:8999"
   :validate-hostnames false}
```

- `:split-conf` - the splitting configuration for the output vector.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `:keep-meta` - whether the metadata should be kept on the processed value;
- `:editable` - St0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

### MQTTSource

This source is used to read from an mqtt queue. This source uses the `[clojurewerkz/machine_head]` library. The source
needs
to have a deserializer configured. These deserializers need to extend the protocol:

`sn0wst0rm-core.protocols.protocols.AQMPDeserializer`

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
- `:error-conf` - the configuration map used by the error function. Optional as you might not be interested to do
  anything with the error itself besides having it logged to the file;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - set to `sn0wst0rm-core.protocols.protocols.MQTTSource`
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - does not have an `x-fn`. All other functions can be used, besides `:forward-fn` which can only be used by sinks.
- `:mqtt-source-topic` - the topic to read from;
- `:mqtt-source-address` - the source address to connect to;
- `:mqtt-source-qos` - the quality of service level (0,1,2);
- `:mqtt-source-conn-optns` - the options needed according to the library used;
- `:deserializer` - the deserializer class to deserialize the data received.
By default, `sn0wst0rm-core.protocols.impl/->NippyDeserializer`is used.
- `:split-conf` - the splitting configuration for the output vector.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `:keep-meta` - whether the metadata should be kept on the processed value;
- `:editable` - St0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

### RabbitMQSource

This source is used to read from an mqtt queue. This source uses the `[com.novemberain/langohr]` library. The source
needs to have a deserializer configured. These deserializers need to extend the protocol:

`sn0wst0rm-core.protocols.protocols.AQMPDeserializer`

There's extra configuration needed that is expressed as a map:

- `:q-conf` - the configuration of the queue:

```
{:qname "iacts.import.users"
 :durable true
 :exclusive false
 :auto-delete false}
```

- `:broker-conf` - the configuration of the broker:

```
{:host "172.20.0.11"
 :port 5672}
```

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
- `:error-conf` - the configuration map used by the error function. Optional as you might not be interested to do
  anything with the error itself besides having it logged to the file;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - set to `sn0wst0rm-core.protocols.protocols.RabbitMQSource`
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - does not have an `x-fn`. All other functions can be used, besides `:forward-fn` which can only be used by sinks.
- `:q-conf` - the queue configuration;
- `:broker-conf` - the broker connection configuration;
- `:auto-ack` - whether the read creates an auto acknowledgement;
- `:exclusive` - whether the queue is exclusive to this consumer;
- `:consumer-tag` - the name/tag of the consumer;
- `:deserializer` - the deserializer class to deserialize the data received. By default, 
`sn0wst0rm-core.protocols.impl/->NippyDeserializer`is used.
- `:split-conf` - the splitting configuration for the output vector.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `:keep-meta` - whether the metadata should be kept on the processed value;
- `:editable` - St0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

Refer to Langhor documentation, for extra properties, etc that you can use in message conf and other specific configurations.
Github link - https://github.com/michaelklishin/langohr

## Pre implemented grinders

### FilePartitionerGrinder

This grinder is used to read from a file and partition its content into segments of n lines.

- `:name` - the name of the step;
- `:error-conf` - the configuration map used by the error function. Optional as you might not be interested to do
  anything with the error itself besides having it logged to the file;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:batch-size` - the number of lines to use in each batch;
- `:type` - set to `sn0wst0rm-core.protocols.protocols.FilePartitionerGrinder`
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - does not have an `x-fn`. All other functions can be used, besides `:forward-fn` which can only be used by sinks.
- `:split-conf` - the splitting configuration for the output vector.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `:keep-meta` - whether the metadata should be kept on the processed value;
- `:editable` - St0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

## Pre implemented enrichers

### DatomicEnricher

This enricher is used to enrich data with the result of datomic query, through a mixing function. It updates its cache,
by executing a datomic query periodically.

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
- `:error-conf` - the configuration map used by the error function. Optional as you might not be interested to do
  anything with the error itself besides having it logged to the file;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - set to `sn0wst0rm-core.protocols.protocols.DatomicEnricher`
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:cache-poll-frequency` - the poll frequency for the enricher cache. How long should it wait to run the query function
  again;
  Needs `time-unit`
- `:cache-time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - as explained above, needs to be a map of key/function. The source, particularly needs `:x-fn`, `q-fn` and `m-fn`.
  - `x-fn` - The mixing function. Takes the value from the queue and mixes it with the cache. 
  Takes 4 arguments `[thread-number conf value cache]`.
  - `:q-fn` - takes 2 arguments `[conn query-args]`, `conn` - the datomic connection, `query-args` - the arguments needed
    for the query to run properly (vector);
  - `m-fn` - The mapping function. The function that takes the query result and maps it to the format the cache needs.
    Takes 1 argument `[value]`. `value` - the result of the query function.
  - All other functions can be used, besides `:forward-fn` which can only be used by sinks.
- `:query-args` - a vector that contains all the arguments necessary to the query execution.
- `:db-name` - contains the name of the db we are trying to connect to.
- `:timeout` - a long value with the amount of time the connector will wait to establish a successful datomic connection.
- `:db-cfg` - a map that contains the necessary elements to establish a datomic connection, like:

```
  {:server-type :peer-server
   :access-key :env
   :secret :env
   :endpoint "sn0wf1eld.com:8999"
   :validate-hostnames false}
```

- `:split-conf` - the splitting configuration for the output vector.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `:keep-meta` - whether the metadata should be kept on the processed value;
- `:editable` - St0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

## Pre implemented sinks

### DatomicSink

This sink is used to save data to Datomic.

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
- `:error-conf` - the configuration map used by the error function. Optional as you might not be interested to do
  anything with the error itself besides having it logged to the file;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - set to `sn0wst0rm-core.protocols.protocols.DatomicSink`
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - as explained above, needs to be a map of key/function. The source, particularly needs `:x-fn`.
  - `x-fn` - The function ran to save data to the db. Takes 4 arguments `[thread-number conf value]`.
  - All other functions can be used.
- `:db-name` - contains the name of the db we are trying to connect to.
- `:timeout` - a long value with the amount of time the connector will wait to establish a successful datomic connection.
- `:db-cfg` - a map that contains the necessary elements to establish a datomic connection, like:

```
  {:server-type :peer-server
   :access-key :env
   :secret :env
   :endpoint "sn0wf1eld.com:8999"
   :validate-hostnames false}
```

These configs, can use the global state reference, or environment variable reference, explained above

- `:split-conf` - the splitting configuration for the output vector.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `:keep-meta` - whether the metadata should be kept on the processed value;
- `:editable` - St0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.
- `:return-xfn-res?` - Whether the result of the sink `x-fn` function should be used for post processing. If set to `false`,
the input of the sink will be used, if set to `true` the result of the sink function will be used.

NOTE: any `x-fn` function used in a sink, should never return the result of the `x-fn` function if the last statement
in that function, returns an object or a set of objects that are not serializable.

### JDBCSink

This sink is used to save data to a JDBC type database.

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
- `:error-conf` - the configuration map used by the error function. Optional as you might not be interested to do
  anything with the error itself besides having it logged to the file;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - set to `sn0wst0rm-core.protocols.protocols.JDBCSink`
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - as explained above, needs to be a map of key/function. The source, particularly needs `:x-fn`.
  - `x-fn` - The function ran to save data to the db. Takes 4 arguments `[thread-number conf value]`.
  - All other functions can be used.
- `:query-args` - a vector that contains all the arguments necessary to the query execution.
- `:timeout` - a long value with the amount of time the connector will wait to establish a successful datomic connection.
- `:db-cfg` - a map that contains the necessary elements to establish a JDBC connection, like:

```
  {:dbtype "postgres"
   :dbname "test"
   :host "127.0.0.1"
   :port 5432
   :user "postgres"
   :password "postgres"}
```
These configs, can use the global state reference, or environment variable reference, explained above

- `:split-conf` - the splitting configuration for the output vector.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `:keep-meta` - whether the metadata should be kept on the processed value;
- `:editable` - St0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.
- `:return-xfn-res?` - Whether the result of the sink `x-fn` function should be used for post processing. If set to `false`,
  the input of the sink will be used, if set to `true` the result of the sink function will be used. By default, 
  the value is set to false.

NOTE: any `x-fn` function used in a sink, should never return the result of the `x-fn` function if the last statement 
in that function, returns an object or a set of objects that are not serializable.

### MQTTSink

This sink is used to output messages to MQTT

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
- `:error-conf` - the configuration map used by the error function. Optional as you might not be interested to do
  anything with the error itself besides having it logged to the file;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - set to `sn0wst0rm-core.protocols.protocols.DatomicEnricher`
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - as explained above, needs to be a map of key/function. The source doesn't have an `x-fn`.
  - All other functions can be used.
- `:timeout` - a long value with the amount of time the connector will wait to establish a successful datomic connection.

Conf for this step should contain:

```
{:mqtt-sink-topic "topic"
 :mqtt-sink-qos 0
 :mqtt-sink-address 127.0.0.1
 :mqtt-sink-conn-optns options}
 
  Options (all keys are optional):

    * :client-id: a client identifier that is unique on the server being connected to
    * :persister: the persistence class to use to store in-flight message; if bil then the
       default persistence mechanism is used
    * :opts: see Mqtt connect options below
    * :on-connect-complete: function called after connection to broker
    * :on-connection-lost: function called when connection to broker is lost
    * :on-delivery-complete: function called when sending and delivery for a message has
       been completed (depending on its QoS), and all acknowledgments have been received
    * :on-unhandled-message: function called when a message has arrived and hasn't been handled
       by a per subscription handler; invoked with 3 arguments:
       the topic message was received on, an immutable map of message metadata, a byte array of message payload

    Mqtt connect options: either a map with any of the keys bellow or an instance of MqttConnectOptions

    * :username (string)
    * :password (string or char array)
    * :auto-reconnect (bool)
    * :connection-timeout (int)
    * :clean-session (bool)
    * :keep-alive-interval (int)
    * :max-in-flight (int)
    * :socket-factory (SocketFactory)
    * :will {:topic :payload :qos :retain}
```
These configs, can use the global state reference, or environment variable reference, explained above


- `:split-conf` - the splitting configuration for the output vector.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `:keep-meta` - whether the metadata should be kept on the processed value;
- `:editable` - St0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.
- `:return-xfn-res?` - Whether the result of the sink `x-fn` function should be used for post processing. If set to `false`,
  the input of the sink will be used, if set to `true` the result of the sink function will be used. 
  By default, the value is set to false.

NOTE: any `x-fn` function used in a sink, should never return the result of the `x-fn` function if the last statement
in that function, returns an object or a set of objects that are not serializable.

### RabbitMQSink
 topic message-conf serializer

This sink is used to output messages to RabbitMQ. RabbitMQ specialized steps, use langhor as the library to be able to 
connect to the rabbit mq server. Refer to the project's documentation in order to know specific properties to use in 
certain methods.

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
- `:error-conf` - the configuration map used by the error function. Optional as you might not be interested to do
  anything with the error itself besides having it logged to the file;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - set to `sn0wst0rm-core.protocols.protocols.DatomicEnricher`
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - as explained above, needs to be a map of key/function. The source doesn't have an `x-fn`.
  - All other functions can be used.
- `:timeout` - a long value with the amount of time the connector will wait to establish a successful datomic connection.
- `:broker-conf` - the configuration to connect to the rabbitmq server. Example:

```
{:host :global/rabbitmq-host
 :port :global/rabbitmq-host-port
 :automatically-recover true}
```

- `:q-conf` - the configuration of the queue. Like:

```
{:qname "name of the queue"}
```

- `:exchange` - The name of the rabbitmq exchange to use to connect to the server.
- `:topic` - The name of the topic used to send the message to the server.
- `:serializer` - These serializers need to extend the protocol `sn0wst0rm-core.protocols.protocols.AQMPSerializer`.
Pre implemented one exists, which uses Nippy `sn0wst0rm-core.protocols.impl/->NippySerializer`
- `:message-conf` - The message configuration.
- `:split-conf` - the splitting configuration for the output vector.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `:keep-meta` - whether the metadata should be kept on the processed value;
- `:editable` - St0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.
- `:return-xfn-res?` - Whether the result of the sink `x-fn` function should be used for post processing. If set to `false`,
  the input of the sink will be used, if set to `true` the result of the sink function will be used.
  By default, the value is set to false.

Refer to Langhor documentation, for extra properties, etc that you can use in message conf and other specific configurations.
Github link - https://github.com/michaelklishin/langohr

NOTE: any `x-fn` function used in a sink, should never return the result of the `x-fn` function if the last statement
in that function, returns an object or a set of objects that are not serializable.

### EmailSink

This sink is used to send emails.


editable keep-meta conf error-conf return-xfn-res?

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
- `:error-conf` - the configuration map used by the error function. Optional as you might not be interested to do
  anything with the error itself besides having it logged to the file;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - set to `sn0wst0rm-core.protocols.protocols.EmailSink`
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
  Needs `time-unit`
- `:threads` - the number of threads used to run this source (default is 1);
- `:timeout` - a long value with the amount of time the connector will wait to establish a successful datomic connection.
- `:split-conf` - the splitting configuration for the output vector.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `:keep-meta` - whether the metadata should be kept on the processed value;
- `:editable` - St0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.
- `:return-xfn-res?` - Whether the result of the sink `x-fn` function should be used for post processing. If set to `false`,
  the input of the sink will be used, if set to `true` the result of the sink function will be used. By default,
  the value is set to false.

- `:conf` - needs to have the following:

```
{:user "AKIAIDTP........"
 :pass "AikCFhx1P......."
 :host "email-smtp.us-east-1.amazonaws.com"
 :port 587}
```

There's a particularity about this sink, if you want to send an email to multiple different accounts, the configuration
mentioned above, can be added to the metadata of the value you want to send as an email. The metadata will be given priority
i.e. if the value as configuration as metadata, it will use that configuration over the one configured in the step, to send
the email. It will default to the one in the configuration file, if no metadata is present.

The value to be processed by this sink, needs to look something like this:

```
{:from "me@draines.com"
  :to "foo@example.com"
  :subject "Hi!"
  :body [{:type "text/html"
          :content "<b>Test!</b>"}
         {:type :attachment
          :content (java.io.File. "/tmp/foo.txt")}
         {:type :inline
          :content (java.io.File. "/tmp/a.pdf")
          :content-type "application/pdf"}]}
```

The base library used for this sink, is `postal` - https://github.com/drewr/postal

NOTE: any `x-fn` function used in a sink, should never return the result of the `x-fn` function if the last statement
in that function, returns an object or a set of objects that are not serializable.


## Error Sink

The error sink is used to process all errors occurred within the instance. It is configured in isolation form the pipelines,
since all pipelines will share the same error sink.

`:error-sink` - processes all framework errors. It executes the configured `error-fn` of the step where the error occurred, 
if no function is specified, it will log the error to the log file;

A default configuration that can be used is:

``` 
{:poll-frequency 500
 :time-unit "ms"
 :threads 1}
```
