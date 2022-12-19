![Alt text](resources/Sn0wSt0rm.png "Optional title")


Sn0wst0rm is built to process and "grind" data.
Receive data from anywhere, process it, and store it however and wherever you want.

# Usage

## Docker

Go to docker directory in sn0wst0rm project and execute:

```
./run-version.sh --version 1.0.0-alpha --maxHeap 4G --minHeap 2G --config /path/to/config.edn --library /path/to/library.jar --env production
```

## Direct jar execution

Go to the scripts folder and use:

```
./grind.sh --maxHeap 4G --minHeap 2G --baseLibrary /path/to/sn0wst0rm/jar --config /path/to/config.edn --library /path/to/library.jar
```

If you want to debug the pipeline, use:

```
./grind-debug.sh --maxHeap 4G --minHeap 2G --baseLibrary /path/to/sn0wst0rm/jar --config /path/to/config.edn --library /path/to/library.jar
```

## Summary

Sn0wst0rm uses .edn files as the main way to configure a pipeline.

A simple pipeline may be composed by 4 things:

- A source;
- A grinder;
- An enhancer;
- A sink;
- A job.

The source is part of the pipeline that retrieves the data to be processed;
The grinder is responsible for processing the data and output the data in the format that is required;
The enhancer is used to enrich processed or collected data with cached data from another source, this source
might be a DB, a file, etc;
The sink is responsible for outputting the processed data, be it a DB or a cloud platform, etc;
The job is responsible for running at a specific scheduled point in time, and it can perform whatever it is needed
out of it, like loading data from a database and outputting, refreshing cached data, etc.

It is not mandatory although, to have a grinder, you can easily save the data from the source directly with a sink,
if that is what is needed for that specific data source.

## Configuration
```
{:api-server #profile {:default {:port 8181}
                       :staging {:port 8181}
                       :production {:port 8181}}
 :steps #profile {:default {:threads-type :virtual
                            :tx-manager {:type :mem
                                         :conf {:file "/Users/iceman/Desktop/transactions.bin"}}
                            :global-state-manager {:type :mem
                                                   :conf {}}
                            :processing-type :local
                            :queue-conf {:buffer-size 100}
                            :sources [{:name "socket-receiver"
                                       :tx {:fail-fast? true
                                            :clean-up-fn (fn [_ _])
                                            :retries 0}
                                       :buffer-size 3
                                       :port 9887
                                       :connects-to ["basecommand-grinder"]
                                       :type coms-middleware.core/map->SocketServerSource
                                       :threads 1}]
                            :grinders [{:name "basecommand-grinder"
                                        :tx {:fail-fast? true
                                             :clean-up-fn (fn [_ _])
                                             :retries 2}
                                        :car-id "0ffb0099-92b2-41dd-a5c1-b7893b1f93a5"
                                        :db-cfg {:dbtype "postgres"
                                                 :dbname "test"
                                                 :host "127.0.0.1"
                                                 :port 5432
                                                 :user "postgres"
                                                 :password "postgres"}
                                        :connects-to ["dashboard-sink"]
                                        :type coms-middleware.core/map->BaseCommandGrinder
                                        :poll-frequency 1
                                        :time-unit "ms"
                                        :threads 1}]
                            :sinks [{:name "dashboard-sink"
                                     :tx {:fail-fast? true
                                          :clean-up-fn (fn [_ _])
                                          :retries 0}
                                     :destination-host "127.0.0.1"
                                     :destination-port 4444
                                     :poll-frequency 1
                                     :time-unit "ms"
                                     :type coms-middleware.core/map->DashboardSink
                                     :threads 1}
                                    {:name "jdbc-sink"
                                     :tx {:fail-fast? true
                                          :clean-up-fn (fn [_ _])
                                          :retries 0}
                                     :car-id "the-car-id"
                                     :db-name "twitter"
                                     :db-cfg {:dbtype "postgres"
                                              :dbname "test"
                                              :host "127.0.0.1"
                                              :port 5432
                                              :user "postgres"
                                              :password "postgres"}
                                     :fns {:x-fn coms-middleware.core/add-to-db}
                                     :type sn0wst0rm-core.protocols.impl/map->JDBCSink
                                     :poll-frequency 1
                                     :time-unit "ms"
                                     :threads 1}]
                            :jobs [{:name "dummy-job"
                                    :tx {:fail-fast? false
                                         :clean-up-fn (fn [_ _])
                                         :retries 0}
                                    :schedule "/30 * * * * * *"
                                    :connects-to ["jdbc-sink"]
                                    :fns {:x-fn coms-middleware.core/save-base-command}}]
                            :error-sink {:fns {:x-fn (fn [_ _ e] (clojure.tools.logging/error "Error found" e))}
                                         :poll-frequency 500
                                         :time-unit "ms"
                                         :threads 1}}
                  :staging {}
                  :production {}}}
```

The current version of sn0wst0rm, contains 2 main configuration points:

- API Server;
- Steps;

## API Server

The api server contains all the information for the API part of sn0wst0rm.
This provides the user information about how many errors have occurred on specific steps,
or a general view of the entire pipeline.

Its configuration for the moment, is composed only of the port where the server is going to be running.

## Steps

The steps contain everything related to the pipeline, i.e. everything from the pipes (queues) to the steps themselves.
As mentioned above, there are multiple types of steps that can be used in the configuration. These need to be added to
the respective vector inside the configuration. Therefor we will end up with:

`:sources []` - for all the sources used in the pipeline;

`:grinders []` - for all the grinders used in the pipeline;

`:enrichers []` - for all the enrichers used in the pipeline;

`:sinks []` - for all the sinks used in the pipeline;

`:jobs []` - for all the jobs used in the pipeline;

each type has common arguments with all other steps, as well as custom ones, that are only used in that specific step.

NOTE: Splitters and demuxi were removed, and are now basically merged into every step. In order to split a value, an extra key
needs to be addded to the step conf called `:step-conf` like so:

```
...
:step-conf {:group-size 50}
...
```


### Tx

After version 0.3.0, the concept of transactions was implemented in this framework. In this scope, a transaction is
a set of operations that need to happen successfully, for an operation to be classified as successful. In order to have
the verification of success, we have the concept of `clean-up-fn`, which is used to check on the transaction, when it is
terminated, and verify its status, depending on the final status (success/failure) it will perform a different task.
For instance, we need to have a file moved at the end of a certain process, it will either end up on the success folder,
if successful, or in the failed folder, if that wasn't the case. It also helps if there are I/O operations in the middle
of the pipeline, where it can be used to rollback changes in the DB mid flight.

The tx configuration usually can look like this:

```
:tx {:clean-up-fn (fn [_ tx]
                      (let [shards (tx/getShards tx)
                           {object :object file :file}  (tx-shard/getValue (first shards))
                           [file parent fname] (if file
                                                   [file (-> file .getAbsoluteFile .getParent) (.getName file)]
                                                   (let [fpath  (-> object
                                                                    :metadata
                                                                    (json/read-str :key-fn keyword)
                                                                    :filename)
                                                         file   (clojure.java.io/file fpath)
                                                         parent (->> (re-pattern "/")
                                                                     (str/split fpath)
                                                                     butlast
                                                                     (str/join (re-pattern "/")))
                                                         fname  (-> fpath
                                                                    (str/split (re-pattern "/"))
                                                                    last)]
                                                                    [file parent fname]))]
                           (if (tx/isSuccessful tx)
                               (.renameTo file (clojure.java.io/file (str parent "/success/" fname ".ok")))
                               (.renameTo file (clojure.java.io/file (str parent "/failure/" fname ".err"))))))
    :fail-fast? false
    :retries 5}
```

Each tx can have the following keys in its config:

- `:clean-up-fn` -  a function that takes 2 arguments (this, which is meant for the step that is calling it, and tx which
  is the transaction record that needs to be analysed);
- `:fail-fast?` - this is the flag that decides if an exception was to occur, would we stop the entire processing pipeline
  or not. For instance, if the entire system is dependent on a database, maybe it is better to gracefully stop it, than to
  risk losing data.
- `:retries` - this is used to set the number of retries we want to happen if something fails. If the step in question is \
  dependent on an external system, and it fails the processing of the data, we might want to retry an x amount of times
  before we actually give up and execute the cleanup function.

## Thread type

Since Sn0wSt0rm was updated to use JDK19 (until the next LTS is out), Virtual threads were added, and to use them in the
thread pools that the framework uses, you just need to set the `:threads-type` to `:virtual`. If you want to use platform
threads, then set it to `:platform`. By default platform threads are used.

## Tx Manager

Since the concept of transactions was introduced, we need a way to manage these transactions, so the tx-manager was introduced
as well. It is responsible for handling transactions operations (creating/deleting/etc).

The tx-manager configuration is mandatory, although, if there isn't a tx-manager that is properly configured, it will try
to default to in-memory managed type (:mem).

The configuration that needs to be added to the steps configuration looks like the following:

```
:tx-manager {:type :mem
             :conf {:file "/Users/iceman/Desktop/transactions.edn"}}
```
It contains the following:

`:type` - the type of manager to be used (currently only :mem is supported);
`:conf` - contains the specific configuration for the transaction manager (in the case of the :mem type, we need a file location).

When the transaction manager was introduced, it was done so to enable the serialization of current operations, i.e. to make sure
that the `in-flight` data is not lost. To do so, we need to serialize the in-flight objects and flush them to disk, and,
if present, load them back from disk, and continue processing when the service is restarted. For the :mem tx-manager,
this translates to having a `:file` configuration, to know exactly where to save/load that data from.

## Global State Manager

The global state manager, as the name indicates is a way to handle data that needs to be shared across multiple steps.
This should only be used in extreme cases, where there's actually the need to do so.

Same as the tx-manager, it too only takes two configuration arguments:

```
:global-state-manager {:type :mem
                       :conf {}}
```

`:type` - the type of manager to be used (currently only :mem is supported);
`:conf` - contains the specific configuration for the transaction manager;

## Processing Type
With the new ability to spit the processing of the pipeline between multiple machines, thanks to the Clojure Message Broker,
we need a way to specify if we want a local only execution, or a distributed one. The processing type was then introduced,
and depending on the choice made (local or distributed), this will have a direct impact on the way the queues are configured.

For local execution we use:
```
:processing-type :local
```

For distributed:

```
:processing-type :distributed
```

### Queue conf

Depending on the processing type, the queues can have different configurations. If local, then the only configuration
possible is the buffer size:

```
:queue-conf {:buffer-size 10}
```

If distributed, the brokers needs to be specified, so that it knows exactly how and where to connect to:
```
:queue-conf {:brokers [["clojure-message-broker" 8888]]
             :buffer-size 10}
```

## Steps Configuration

With this latest iteration of the framework (v 0.9.9+), it was decided to simplify the configuration process.
Now we have a base configuration that can be used by every step, and it looks like the following:

```
{:name "tweet-importer"
 :tx {:fail-fast? false
      :clean-up-fn (fn [a b] (clojure.tools.logging/info "Transaction cleaned!"))
      :retries 2}
 :connects-to ["tweet-interpreter"]
 :fns {:x-fn twitter-hashtag-counter.core/get-data
       :v-fn (fn [v])
       :sw-fn (fn [this name tx connects-to value])}
 :type sn0wst0rm-core.protocols.impl/map->DatomicSink
 :poll-frequency 500
 :time-unit "us"
 :threads 1}
```

- `:name` - the name of the step;
- `tx` - the transactional configuration, it contains the following:
    - `:fail-fast?` - whether or not the system should be shutdown if an exception is detected while executing this step's function.
    - `:retries` - the number of times a failure should be retried before continuing on to the next execution.
    - `clean-up-fn` - the function that will be executed once the transaction is finished. This can be a function to move a file,
      to a different place, change the status of an object in the db, etc.

- `:fns` - a map containing keys as function names and values as either function code, or function path. Like so:

```
:fns {:x-fn twitter-hashtag-counter.core/get-data
      :v-fn (fn [v])
      :sw-fn (fn [this name tx connects-to value])}
```

In the case above, we have a transformation function that was declared somewhere else (`:x-fn`), a validation function
that is declared directly in the config (`:v-fn`) and a switching function (`:sw-fn`) that decides where the output is directed
depending on the value.

- `:type` - this is used in case we have a predefined source type (an external library for instance) that was previously
  implemented. If this is not present, then it will try to check if a custom function(x-fn) is present to use as a source;
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);

## Sources Configuration

Each generic source has the following arguments:

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the transformation function.
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step should be specified as a string.
- `:type` - this is used in case we have a predefined source type (an external library for instance) that was previously
  implemented. If this is not present, then it will try to check if a custom function(x-fn) is present to use as a source;
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - as explained above, needs to be a map of key/function. The source, particularly needs `:x-fn` and `:v-fn`.
  These are mandatory, the first one is the function that needs to be executed at the specified frequency, and should have an
  arity of 2, first argument should be the thread number, and second one should be conf. The second one is the validation
  function, and takes a single argument, conf and outputs a vector of validation messages, if the vector is empty, it means
  that the configuration is valid.

## Grinders Configuration

Each generic Grinder has the following arguments

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the transformation function.
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step should be specified as a string.
- `:type` - this is used in case we have a predefined source type (an external library for instance) that was previously
  implemented. If this is not present, then it will try to check if a custom function(x-fn) is present to use as a source;
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - as explained above, needs to be a map of key/function. The source, particularly needs `:x-fn` and `:v-fn`.
  These are mandatory, the first one is the function that needs to be executed at the specified frequency, and should have an
  arity of 3, first argument should be the thread number, and second one should be conf and the last one should the value that
  is going to be grinded.
  The second one is the validation function, and takes a single argument, conf and outputs a vector of validation messages,
  if the vector is empty, it means that the configuration is valid.

## Enrichers Configuration

Each generic Enricher has the following arguments

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the transformation function.
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step should be specified as a string.
- `:type` - this is used in case we have a predefined source type (an external library for instance) that was previously
  implemented. If this is not present, then it will try to check if a custom function(x-fn) is present to use as a source;
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:cache-poll-frequency` - the pool frequency in milliseconds at which the cache is refreshed. Needs `:cache-time-unit`
- `:cache-time-unit` - the time unit to be used by the cache (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - as explained above, needs to be a map of key/function. The source, particularly needs `:x-fn`, `:v-fn` and `c-fn`.
  These are mandatory, the first one is the function that needs to be executed at the specified frequency, and should have an
  arity of 4, first argument should be the thread number, and second one should be conf, the third one should the value that
  is going to be enriched and finally the last one is the cache.
  The second one is the validation function, and takes a single argument, conf and outputs a vector of validation messages,
  if the vector is empty, it means that the configuration is valid.
  The last function is the cache function, takes no arguments, and its output is meant to replace the current cache value.

## Sinks Configuration

Each generic Sink has the following arguments

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the transformation function.
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step should be specified as a string.
- `:type` - this is used in case we have a predefined source type (an external library for instance) that was previously
  implemented. If this is not present, then it will try to check if a custom function(x-fn) is present to use as a source;
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - as explained above, needs to be a map of key/function. The source, particularly needs `:x-fn` and `:v-fn`.
  These are mandatory, the first one is the function that needs to be executed at the specified frequency, and should have an
  arity of 3, first argument should be the thread number, and second one should be conf and the last one should the value that
  is going to be sinked.
  The second one is the validation function, and takes a single argument, conf and outputs a vector of validation messages,
  if the vector is empty, it means that the configuration is valid.

## Jobs Configuration

Each job has the following arguments

- `:name` - the name of the step;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step should be specified as a string.
- `:fns` - as explained above, needs to be a map of key/function. The source, particularly needs `:x-fn`.
  These are mandatory, the first one is the function that needs to be executed at the specified frequency,
  and it shouldn't have any arguments. This function is meant to generate events at a specified time, and output them
  to another step that will be responsible for executing the task.
- `:schedule` -  a cron like string responsible for creating the execution behaviour of the job.
