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
                                                   :conf {}
                                                   :state {:db-type "postgres"
                                                           :db-name "test"}}
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
                                        :error-conf {:some-config "this is a value"}
                                        :db-cfg {:dbtype :global/db-type
                                                 :dbname :global/db-name
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
                            :error-sink {:poll-frequency 500
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

`:error-sink` - the sink that processes all framework errors. It executes the configured `error-fn` of the step where the
error occurred, if not function is specified, it will log the error to the log file;

each type has common arguments with all other steps, as well as custom ones, that are only used in that specific step.

NOTE: Splitters and demuxi were removed, and are now basically merged into every step. In order to split a value, an
extra key needs to be added to the step conf called `:step-conf` like so:

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
of the pipeline, where it can be used to rollback changes in the DB mid-flight.

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

- `:clean-up-fn` - a function that takes 2 arguments (this, which is meant for the step that is calling it, and tx which
  is the transaction record that needs to be analysed);
- `:fail-fast?` - this is the flag that decides if an exception was to occur, would we stop the entire processing
  pipeline
  or not. For instance, if the entire system is dependent on a database, maybe it is better to gracefully stop it, than
  to
  risk losing data.
- `:retries` - this is used to set the number of retries we want to happen if something fails. If the step in question
  is \
  dependent on an external system, and it fails the processing of the data, we might want to retry an x amount of times
  before we actually give up and execute the cleanup function.

## Thread type

Since Sn0wSt0rm was updated to use JDK19 (until the next LTS is out), Virtual threads were added, and to use them in the
thread pools that the framework uses, you just need to set the `:threads-type` to `:virtual`. If you want to use
platform
threads, then set it to `:platform`. By default platform threads are used.

## Tx Manager

Since the concept of transactions was introduced, we need a way to manage these transactions, so the tx-manager was
introduced
as well. It is responsible for handling transactions operations (creating/deleting/etc).

The tx-manager configuration is mandatory, although, if there isn't a tx-manager that is properly configured, it will
try
to default to in-memory managed type (:mem).

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
make sure
that the `in-flight` data is not lost. To do so, we need to serialize the in-flight objects and flush them to disk, and,
if present, load them back from disk, and continue processing when the service is restarted. For the :mem tx-manager,
this translates to having a `:file` configuration, to know exactly where to save/load that data from. This might eventually 
be replaced with CRAC, which allows to snapshot a JVM execution state, removing the need for serialization.

## Global State Manager

The global state manager, as the name indicates is a way to handle data that needs to be shared across multiple steps.
This should only be used in extreme cases, where there's actually the need to do so.

Same as the tx-manager, it too only takes two configuration arguments:

```
:global-state-manager {:type :mem
                       :conf {}
                       :state {}}
```

`:type` - the type of manager to be used (currently only :mem is supported);
`:conf` - contains the specific configuration for the transaction manager;
`:state` - contains all current state, which means common configurations can be added once and shared across multiple steps.

This concept is really useful, since it means you don't need to repeat the config anywhere. Let's say you want to configure
the db details for a JDBC connection once, and then use it in multiple places, this is what you would do in the global-state-manager:

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

Notice the `:global` prefix of the keyword, this lets the framework initializer that the config it needs on that specific 
step is present in the global state.

We also provide a way to resolve environment variables, basically instead of using the prefix `:global` 
you use the prefix `:env`. 

You can also mix and match both of them, what I mean by this is, you can refer to a global configuration within a step,
and in turn a global config can refer to an environment variable. Let's say you want to configure a db connection once again,
but you want to keep the password to the connection safe in a environment variable, you would do the following:

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

This would make the initializer look for the `db-cfg` in the global state, and then for the `db-password` in the environment
variable `DB_PASSWORD`.

### Queue conf

Depending on the processing type, the queues can have different configurations. If local, then the only configuration
possible is the buffer size:

```
:queue-conf {:buffer-size 10}
```

## Steps Configuration

With this latest iteration of the framework (v 0.9.9+), it was decided to simplify the configuration process.
Now we have a base configuration that can be used by every step, and it looks like the following:

```
{:name "tweet-importer"
 :await-termination-time 2000
 :editable true
 :batch-size 100
 :tx {:fail-fast? false
      :clean-up-fn (fn [a b] (clojure.tools.logging/info "Transaction cleaned!"))
      :retries 2}
 :connects-to ["tweet-interpreter"]
 :split-conf {:group-size 50}
 :error-conf {:some-conf "value"}
 :fns {:x-fn twitter-hashtag-counter.core/get-data
       :v-fn (fn [v])
       :sw-fn (fn [this name tx connects-to value])
       :error-fn (fn [this conf error])}
 :keep-meta true
 :type sn0wst0rm-core.protocols.impl/map->DatomicSink
 :poll-frequency 500
 :time-unit "us"
 :threads 1}
```

- `:name` - the name of the step;
- `:await-termination-time` - when stopping the system, this is the time (ms) the step executor will wait for all tasks
  to finish,
  if this value is not provided, it will default to 1000 (ms).
- `:editable` - whether the value that has failed to be processed by this step, is or not editable from the UI (defaults
  to false);
- `:batch-size` - batch processing is now enabled in the system, set this value to a specific number to set the batch
  size. No key added, will make the system default to single value processing;
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
    - `clean-up-fn` - the function that will be executed once the transaction is finished. This can be a function to
      move a file,
      to a different place, change the status of an object in the db, etc.
- `error-conf` - the configuration map used by the error function. Optional as you might not be interested to do anything 
with the error itself besides having it logged to the file;
- `:fns` - a map containing keys as function names and values as either function code, or function path. Like so:

```
:fns {:x-fn twitter-hashtag-counter.core/get-data
      :v-fn (fn [v])
      :sw-fn (fn [this name tx connects-to value])
      :error-fn (fn [this conf error])}
```

In the case above, we have a transformation function that was declared somewhere else (`:x-fn`), a validation function
that is declared directly in the config (`:v-fn`) and a switching function (`:sw-fn`) that decides where the output is
directed depending on the value, and finally `error-fn` which, in conjunction with `error-conf` is used to treat the error
generated by the step, and do with it whatever the programmer wants to, like sending it to a queue, printing it in the console,
etc.

These functions have specific arities, and need to be configured accordingly:

- `x-fn` - this is always mandatory on generic steps (might not be in pre implemented ones), but the arity will depend on 
the type of step it is being configured for, so check each one to make sure you are configuring it correctly;
- `v-fn` - optional function, used to validate the configuration (conf) of the step. Takes a single argument.
Will return true by default if not provided.
- `sw-fn` - optional function, used to act as a switch, i.e. route the processed value depending on the result to different channels.
Takes 5 arguments, look for the name of the arguments above, they are quite self-explanatory;
- `error-fn` - optional function, used to treat an error generated by the step. Takes 3 arguments, `this`, `conf` and `error`.
- `keep-meta` - flag that sets the behaviour regarding metadata. If set to true, the metadata will be kept in the processed value, 
otherwise it will be removed;
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
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - this is used in case we have a predefined source type (an external library for instance) that was previously
  implemented. If this is not present, then it will try to check if a custom function(x-fn) is present to use as a
  source;
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `splitted?` - whether the collection/vector of the result should be splitted into single values/transactions; 
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - as explained above, needs to be a map of key/function. The source, particularly needs `:x-fn` and `:v-fn`.
  These are mandatory, the first one is the function that needs to be executed at the specified frequency, and should
  have an arity of 2, first argument should be the thread number, and second one should be conf. The second one is the
  validation function, and takes a single argument, conf and outputs a vector of validation messages, if the vector is empty, it
  means that the configuration is valid.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `keep-meta` - whether the metadata should be kept on the processed value; 
- `:editable` - st0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

## Jobs Configuration

Each job has the following arguments

- `:name` - the name of the step;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `splitted?` - whether the collection/vector of the result should be splitted into single values/transactions;
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:fns` - as explained above, needs to be a map of key/function. The source, particularly needs `:x-fn`.
  These are mandatory, the first one is the function that needs to be executed at the specified frequency,
  and it shouldn't have any arguments. This function is meant to generate events at a specified time, and output them
  to another step that will be responsible for executing the task.
- `:schedule` - a cron like string responsible for creating the execution behaviour of the job.

## Grinders Configuration

Each generic Grinder has the following arguments

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
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
- `:fns` - as explained above, needs to be a map of key/function. The source, particularly needs `:x-fn` and `:v-fn`.
  These are mandatory, the first one is the function that needs to be executed at the specified frequency, and should
  have an arity of 3, first argument should be the thread number, and second one should be conf and the last one should the
  value that is going to be grinded.
  The second one is the validation function, and takes a single argument, conf and outputs a vector of validation
  messages, if the vector is empty, it means that the configuration is valid.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `keep-meta` - whether the metadata should be kept on the processed value; 
- `:editable` - st0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

## Enrichers Configuration

Each generic Enricher has the following arguments

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
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
- `:fns` - as explained above, needs to be a map of key/function. The source, particularly needs `:x-fn`, `:v-fn`and `c-fn`.
  These are mandatory, the first one is the function that needs to be executed at the specified frequency, and should
  have an arity of 4, first argument should be the thread number, and second one should be conf, the third one should the value
  that is going to be enriched and finally the last one is the cache.
  The second one is the validation function, and takes a single argument, conf and outputs a vector of validation
  messages, if the vector is empty, it means that the configuration is valid.
  The last function is the cache function, takes no arguments, and its output is meant to replace the current cache
  value.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `keep-meta` - whether the metadata should be kept on the processed value; 
- `:editable` - st0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

## Sinks Configuration

Each generic Sink has the following arguments

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
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
- `:fns` - as explained above, needs to be a map of key/function. The source, particularly needs `:x-fn` and `:v-fn`.
  These are mandatory, the first one is the function that needs to be executed at the specified frequency, and should
  have an arity of 3, first argument should be the thread number, and second one should be conf and the last one should the
  value that is going to be sinked. The second one is the validation function, and takes a single argument, 
  conf and outputs a vector of validation messages, if the vector is empty, it means that the configuration is valid.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `keep-meta` - whether the metadata should be kept on the processed value; 
- `:editable` - st0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

# Configuration by steps type

Above we can see all available configurations for the generic types, although `sn0wst0rm` contains specific types, that
are pre implemented and allow developers to just use them instead of creating a new one every time they need to implement a
new case.

## Pre implemented sources

### FileWatcherCustomSource

This source is used to watch a specific directory, and load all files that are place in the folder into the designed
pipeline.

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - set to `sn0wst0rm-core.protocols.protocols.FileWatcherCustomSource`
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - besides the possibility of adding `clean-up-fn` and `sw-fn`, there's a mandatory function called
  `:file-filter-fn`. This function takes a single argument (arity of 1), and is used to filter the files detected by the
  source,
  so that the ones sent to the next step are the ones that actually matter.
- `:file-batch-size` - the max number of files read everytime the source runs;
- `:watch-dir` - configures the directory to watch.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `keep-meta` - whether the metadata should be kept on the processed value; 
- `:editable` - st0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

### DatomicSource

This source is used to retrieve data from a datomic database periodically, by executing the same query every time.

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - set to `sn0wst0rm-core.protocols.protocols.DatomicSource`
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - besides the possibility of adding `clean-up-fn` and `sw-fn`, there is another function needed, `q-fn`.
  This extra function is the one executed periodically, takes 2 arguments [conn query-args]. `conn` - the datomic
  connection, `query-args` - the arguments needed for the query to run properly.
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
- `keep-meta` - whether the metadata should be kept on the processed value; 
- `:editable` - st0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

### MQTTSource

This source is used to read from an mqtt queue. This source uses the `[clojurewerkz/machine_head]` library. The source needs
to have a deserializer configured. These deserializers need to extend the protocol:

`sn0wst0rm-core.protocols.protocols.AQMPDeserializer`

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - set to `sn0wst0rm-core.protocols.protocols.MQTTSource`
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - takes`clean-up-fn` and `sw-fn`.
- `:mqtt-source-topic` - the topic to read from;
- `:mqtt-source-address` - the source address to connect to;
- `:mqtt-source-qos` - the quality of service level (0,1,2);
- `:mqtt-source-conn-optns` - the options needed according to the library used;
- `:deserializer` - the deserializer class to deserialize the data received. By default, `sn0wst0rm-core.protocols.impl/->NippyDeserializer`
is used. 
- `:split-conf` - the splitting configuration for the output vector.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `keep-meta` - whether the metadata should be kept on the processed value; 
- `:editable` - st0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

### RabbitMQSource

This source is used to read from an mqtt queue. This source uses the `[com.novemberain/langohr]` library. The source needs
to have a deserializer configured. These deserializers need to extend the protocol:

`sn0wst0rm-core.protocols.protocols.AQMPDeserializer`

There's extra configuration needed that is expressed as a map:

- `q-conf` - the configuration of the queue:

```
{:qname "iacts.import.users"
 :durable true
 :exclusive false
 :auto-delete false}
```

- `broker-conf` - the configuration of the broker:

```
{:host "172.20.0.11"
 :port 5672}
```

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - set to `sn0wst0rm-core.protocols.protocols.RabbitMQSource`
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - takes`clean-up-fn` and `sw-fn`.
- `:q-conf` - the queue configuration;
- `:broker-conf` - the broker connection configuration;
- `:auto-ack` - whether the read creates an auto acknowledgement;
- `:exclusive` - whether the queue is exclusive to this consumer;
- `:consumer-tag` - the name/tag of the consumer;
- `:deserializer` - the deserializer class to deserialize the data received. By default, `sn0wst0rm-core.protocols.impl/->NippyDeserializer`is used.
- `:split-conf` - the splitting configuration for the output vector.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `keep-meta` - whether the metadata should be kept on the processed value; 
- `:editable` - st0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

## Pre implemented grinders

### FilePartitionerGrinder

This grinder is used to read from a file and partition its content into segments of n lines.

- `:name` - the name of the step;
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:batch-size` - the number of lines to use in each batch;
- `:type` - set to `sn0wst0rm-core.protocols.protocols.FilePartitionerGrinder`
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - takes`clean-up-fn` and `sw-fn`.
- `:split-conf` - the splitting configuration for the output vector.
- `:await-for-termination-time` - the time to wait for the threads started by this step to stop
- `keep-meta` - whether the metadata should be kept on the processed value; 
- `keep-meta` - whether the metadata should be kept on the processed value; 
- `:editable` - st0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.

## Pre implemented enrichers

### DatomicEnricher
name threads connects-to fns tx poll-frequency time-unit split-conf execution-state
mutable-state conf error-conf cache cache-poll-frequency cache-time-unit query-args db-cfg db-name
timeout await-for-termination-time editable keep-meta

This enricher is used to enrich data with the result of datomic query, through a mixing function. It updates its cache,
by executing a datomic query periodically.

- `:name` - the name of the step;
- `:conf` - Only present in the generic implementation of Source. Used to hold specific values used by the
  transformation function.
- `:tx` - the transactional configuration, check above to see how to configure it.
- `:connects-to` - this specifies a vector of steps where the output of this step's execution is directed. Each step
  should be specified as a string.
- `:type` - set to `sn0wst0rm-core.protocols.protocols.DatomicEnricher`
- `:poll-frequency` - the poll frequency for the source. How long should it wait to run the source function again;
  Needs `time-unit`
- `:time-unit` - the time unit to be used (m, s, ms, us, ns);
- `cache-poll-frequency` - the poll frequency for the enricher cache. How long should it wait to run the query function again;
  Needs `time-unit`
- `cache-time-unit` - the time unit to be used (m, s, ms, us, ns);
- `:threads` - the number of threads used to run this source (default is 1);
- `:fns` - besides the possibility of adding `clean-up-fn` and `sw-fn`, there are other functions needed:
  - `q-fn` - This extra function is the one executed periodically, takes 2 arguments [conn query-args]:
           `conn` - the datomic connection, `query-args` - the arguments needed for the query to run properly.
  - `m-fn` - The mapping function. The function that takes the query result and maps it to the format the cache needs.
           Takes 1 argument [value]. `value` - the result of the query function.
  - `x-fn` - The mixing function. Takes the value from the queue and mixes it with the cache. Takes 4 arguments [t conf value cache].
           `t` - the thread number that is currently processing the value, `conf` - the eventual configuration map used to mix the data,
           `value` - the received value used to mix with the cache, `cache` - the current cache value;
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
- `keep-meta` - whether the metadata should be kept on the processed value;
- `:editable` - st0rmwatch3r only, configures whether the values gathered by this step are editable in the ui or not.
