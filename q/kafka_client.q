//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//
//                    File Decription                    //
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//

// @file kafka_client.q
// @fileoverview
// Define kafka client interfaces.

//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//
//                     Global Variable                   //
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//

//%% Utility %%//vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv/

// @private
// @kind variable
// @category Utility
// @brief Offset between UNIX epoch (1970.01.01) and kdb+ epoch (2000.01.01) in day.
.kafka.KDB_DAY_OFFSET:10957D;

//%% Client %%//vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv/

// @private
// @kind variable
// @category Client
// @brief Mapping between client and the type of handle created i.e. producer/consumer
.kafka.CLIENT_TYPE_MAP:(`int$())!`symbol$();

//%% Callback %%//vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv/

// @private
// @kind variable
// @category Callback
// @brief Dictionary of error callback functions per client index.
// - key {int}: Client index in `CLIENTS`.
// - value {function}: Callback function called in `error_cb`.
.kafka.ERROR_CALLBACK_PER_CLIENT:enlist[0Ni]!enlist (::);

// @private
// @kind variable
// @category Callback
// @brief Dictionary of throttle callback functions per client index.
// - key {int}: Client index in `CLIENTS`.
// - value {function}: Callback function called in `throttle_cb`.
.kafka.THROTTLE_CALLBACK_PER_CLIENT:enlist[0Ni]!enlist (::);

// @private
// @kind variable
// @category Callback
// @brief Dictionary of consume_callback functions for each topic per client index.
// - key {int}: Client (consumer) index in `CLIENTS`.
// - value {dictionary}: Dictionary of callback function for each topic.
//     - key {symbol}: topic.
//     - value {function}: callback function called inside `.kfk.consume_callback`.
.kafka.CONSUME_TOPIC_CALLBACK_PER_CONSUMER:enlist[0Ni]!enlist ()!();

// @kind variable
// @category Callback
// @brief Kafka statistics table;
.kafka.STATISTICS:();

//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//
//                    Private Functions                  //
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//

//%% Callback %%//vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv/

// https://docs.confluent.io/current/clients/librdkafka/rdkafka_8h.html

// @private
// @kind function
// @category Callback
// @brief Callback function for statistics set by `rd_kafka_conf_set_stats_cb`. Deligated by C function `stats_cb`.
// @param statistics {string}: Statistics in JSON format.
// @note
// This function is triggered from `rd_kafka_poll()` every `statistics.interval.ms`.
.kafka.stats_cb:{[statistics]
  statistics:.j.k statistics;
  if[all `ts`time in key statistics;
    // Convert data to timestamp
    statistics[`ts]:(`timestamp$statistics[`ts]*1000) - .kafka.KDB_DAY_OFFSET;
    statistics[`time]:(`timestamp$1e9*statistics[`time]) - .kafka.KDB_DAY_OFFSET;
  ];
  // Insert the new record
  .kafka.STATISTICS: .kafka.STATISTICS uj enlist statistics;
  // Keep only 100 records
  delete from `.kafka.STATISTICS where i < count[.kafka.STATISTICS]-100;
 };

// @private
// @kind function
// @category Callback
// @brief Callback function for error or warning. Deligated by C function `error_cb`.
// @param client_idx {int}: Index of client.
// @param error_code {int}: Error code.
// @param reason {string}: Reason for the error.
.kafka.error_cb:{[client_idx;error_code;reason]
  // Call registered callback function if any; otherwise call default callback function
  $[(::) ~ registered_error_cb:.kafka.ERROR_CALLBACK_PER_CLIENT client_idx;
    .kafka.default_error_cb;
    registered_error_cb
  ] . (client_idx; error_code; reason)
 };

// @private
// @kind function
// @category Callback
// @brief Callback function for throttle events to request producing and consuming. Deligated by C function `throttle_cb`.
// @param client_idx {int}: Index of client in `CLIENTS`.
// @param broker_name {string}: Name of broker.
// @param broker_id {int}: ID of broker.
// @param throttle_time_ms {int}: Broker throttle time in milliseconds.
.kafka.throttle_cb:{[client_idx;broker_name;broker_id;throttle_time]
  // Call registered callback function if any; otherwise call default callback function
  $[(::) ~ registered_throttle_cb:.kafka.THROTTLE_CALLBACK_PER_CLIENT client_idx;
    .kafka.default_throttle_cb;
    registered_throttle_cb
  ] . (client_idx; broker_name; broker_id; throttle_time)
 };

// @private
// @kind function
// @category Callback
// @brief Callback function for consuming messages triggered by `rd_kafka_consumer_poll()`. Deligated by C function `poll_client`.
// @param consumer_idx {int}: Index of client (consumer) in `CLIENTS`.
// @param message {dictionary}: Dictionary containing a message returned by `rd_kafka_consumer_poll()`.
.kafka.consume_topic_cb:{[consumer_idx; message]
  // Call registered callback function for the topic in the message if any; otherwise call default callback function.
  $[(::) ~ registered_consume_topic_cb:.kafka.CONSUME_TOPIC_CALLBACK_PER_CONSUMER[consumer_idx; message `topic];
     .kafka.default_consume_topic_cb;
     registered_consume_topic_cb
  ] message
 };

//%% Client %%//vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv/

// @private
// @kind function
// @category Client
// @brief Create a client based on a given client type (producer or consumer) and a given configuration.
// @param client_type {char}:
// - "p": Producer
// - "c": Consumer
// @param config {dictionary}: Dictionary containing a configuration.
//  - key: symbol
//  - value: symbol
// @param timeout {int}: Timeout (milliseconds) for querying.
// @param pipeline_name {symbol}: Name of pipeline to use. If transformer library is not used, this parameter is ignored.
// @return
// - error: If passing client type which is neither of "p" or "c". 
// - int: Client index in `CLIENTS`.
.kafka.newClient_impl:LIBPATH_ (`new_client; 4);

// @private
// @kind function
// @category Client
// @brief Create a client based on a given client type (producer or consumer) and a given configuration and then
//  add client type (consumer or producer) to `.kafka.CLIENT_TYPE_MAP`.
// @param client_type {char}:
// - "p": Producer
// - "c": Consumer
// @param config {dictionary}: Dictionary containing a configuration.
//  - key: symbol
//  - value: symbol
// @param timeout {int}: Timeout (milliseconds) for querying.
// @param pipeline_name {symbol}: Name of pipeline to use. If transformer library is not used, this parameter is ignored.
// @return
// - error: If passing client type which is neither of "p" or "c". 
// - int: Client index in `CLIENTS`.
.kafka.newClient:{[client_type;config;timeout;pipeline_name]
  if[(not `group.id in key config) and client_type="c"; '"consumer must define 'group.id' within the config"];
  client:.kafka.newClient_impl[client_type; config; timeout; pipeline_name];
  .kafka.CLIENT_TYPE_MAP,: enlist[client]!enlist[`$client_type];
  client
 };

// @private
// @kind function
// @category Client
// @brief Destroy client handle and remove from `CLIENTS`.
// @param client_idx {int}: Index of client in `CLIENTS`.
.kafka.deleteClient_impl:LIBPATH_ (`delete_client;1);

//%% Poll %%//vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv/

// @private
// @kind function
// @category Poll
// @brief Start polling client in background.
// @param client_idx {int}: Client index in `CLIENTS`.
.kafka.startBackgroundPoll:LIBPATH_ (`start_background_poll; 1);

// @private
// @kind function
// @category Poll
// @brief Stop polling client in background.
// @param client_idx {int}: Client index in `CLIENTS`.
.kafka.stopBackgroundPoll:LIBPATH_ (`stop_background_poll; 1);

//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//
//                    Public Interface                   //
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//

//%% Callback %%//vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv/

// @kind function
// @category Callback
// @brief Callback function to print log set by `rd_kafka_conf_set_log_cb`.
//  Deligated by C function `log_cb`.
// @param level {int}: log level.
// @param fac {string}: WHAT IS THIS??
// @param buf {string}: WHAT IS THIS??
// @todo
// Change output destination by `level`
.kafka.log_cb:{[level;fac;buf]
  // Change if you wish.
  // Default definition for users using deprecated kfk.q.
  $[.kafka.USE_DEPRECATED;
    .kfk.logcb[level; fac; buf];
    -1 .Q.s1 (level; fac; buf)
  ]  
 };

// @kind function
// @category Callback
// @brief Callback function set by `rd_kafka_conf_set_offset_commit_cb` and triggered by `rd_kafka_consumer_poll()`
//  for use with consumer groups. Deligated by C function `offset_commit_cb`.
// @param consumer_idx {int}: client (consumer) index
// @param error {string}: error message
// @param offsets {list of dictionary}: A list of topic-partition information dictionaries
.kafka.offset_commit_cb:{[consumer_idx;error;offsets]
  // Change if you wish.
  // Default definition for users using deprecated kfk.q.
  $[.kafka.USE_DEPRECATED;
    .kfk.offsetcb[consumer_idx; error; offsets];
    // Bother user to encourage them to define something.
    -1 .Q.s1 (consumer_idx;error;offsets)
  ]  
 };

// @kind function
// @category Callback
// @brief Callback function for delivery report set by `rd_kafka_conf_set_dr_msg_cb`.
// @param producer_idx {int}: Index of client (producer).
// @param message {dictionary}: Information conatined in delivery report.
.kafka.dr_msg_cb:{[producer_idx;message]
  // Change if you wish.
  // Default definition for users using deprecated kfk.q.
  $[.kafka.USE_DEPRECATED;
    .kfk.drcb[producer_idx; message];
    // Bother user to encourage them to define something.
    -1 .Q.s1 (producer_idx;message)
  ]  
 };

// @kind function
// @category Callback
// @brief Default callback function for error or warning called inside `.kafka.error_cb`
// @param client_idx {int}: Index of client.
// @param error_code {int}: Error code.
// @param reason {string}: Reason for the error.
.kafka.default_error_cb:{[client_idx;error_code;reason]
  // Change if you wish.
  // Default definition for users using deprecated kfk.q.
  $[.kafka.USE_DEPRECATED;
    .kfk.errclient.[client_idx; error_code; reason];
    -2 .Q.s1 (client_idx; error_code; reason)
  ]
 };

// @kind function
// @category Callback
// @brief Default callback function for throttle events to request producing and consuming. Called inside `.kfk.throttle_cb`.
// @param client_idx {int}: Index of client in `CLIENTS`.
// @param broker_name {string}: Name of broker.
// @param broker_id {int}: ID of broker.
// @param throttle_time_ms {int}: Broker throttle time in milliseconds.
.kafka.default_throttle_cb:{[client_idx;broker_name;broker_id;throttle_time]
  // Change if you wish.
  // Default definition for users using deprecated kfk.q.
  $[.kafka.USE_DEPRECATED;
    .kfk.throttleclient.[client_idx; broker_name; broker_id; throttle_time];
    // Bother user to encourage them to define something.
    -1 .Q.s1 (client_idx; broker_name; broker_id; throttle_time)
  ]
 };

// @kind function
// @category Callback
// @brief Default callback for consuming messages called inside `.kfk.consume_cb`.
// @param message {dictionary}: Dictionary containing a message returned by `rd_kafka_consumer_poll()`.
.kafka.default_consume_topic_cb:{[message]
  // Change if you wish.
  // Default definition for users using deprecated kfk.q.
  $[.kafka.USE_DEPRECATED;
    .kfk.consumetopic.[message];
    // Bother user to encourage them to define something.
    -1 .Q.s1 message
  ]
 };

// @kind function
// @category Callback
// @brief Register error callback function for a given client.
// @param client_idx {int}: Index of client in `CLIENTS`.
// @param callback {function}: Callback function which has following parametrers:
// - `client_idx` {int}: Same client index as the parent function.
// - `error_code` {int}: Error code.
// - `reason` {string}: Reason of the error.
// @note
// Replacement of `.kfk.errcbreg`.
.kafka.registerErrorCallback:{[client_idx;callback]
  .kafka.ERROR_CALLBACK_PER_CLIENT[client_idx]:callback;
 };

// @kind function
// @category Callback
// @brief Register throttle callback function for a given client.
// @param client_idx {int}: Index of client in `CLIENTS`.
// @param callback {function}: Callback function which has following parameters:
// - `client_idx` {int}: Same client index as the parent function.
// - `broker_name` {string}: Name of broker.
// - `broker_id` {int}: ID of broker.
// - `throttle_time_ms` {int}: Broker throttle time in milliseconds.
// @note
// Replacement of `.kfk.throttlecbreg`.
.kafka.registerThrottleCallback:{[client_idx;callback]
  .kafka.THROTTLE_CALLBACK_PER_CLIENT[client_idx]:callback;
 };

// @kind function
// @category Callback
// @brief Register callback at message consumption for a given client and topic.
// @param consumer_idx {int}: Index of client (consumer) in `CLIENTS`.
// @param topic {symbol}: Topic for which calback is to be set.
// @param callback {function}: Callback function which has following parameters:
// - `consumer_idx` {int}: Same consumer index as the parent function.
// - `message` {dictionary}: Dictionary containing a message returned by `rd_kafka_consumer_poll()`.
.kafka.registerConsumeTopicCallback:{[consumer_idx; topic; callback]
  .kafka.CONSUME_TOPIC_CALLBACK_PER_CONSUMER[consumer_idx],: enlist[topic]!enlist callback;
 };

// %% Create/Delete %%//vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv/

// @kind function
// @category Create/Delete
// @brief Create a producer with a given configuration.
// @param config {dictionary}: Dictionary containing a configuration.
// - key: symbol
// - value: symbol
// @param timeout {int}: Timeout (milliseconds) for querying.
// @param pipeline_name {symol}: Name of pipeline to use for encoding a message. If transformer library is not used, this parameter is ignored.
// @return
// - int: Client index in `CLIENTS`.
.kafka.newProducer:{[config;timeout;pipeline_name]
  producer: .kafka.newClient["p"; config; timeout; pipeline_name];
  .kafka.startBackgroundPoll[producer]
 };

// @kind function
// @category Create/Delete
// @brief Create a consumer with a given configuration.
// @param config {dictionary}: Dictionary containing a configuration.
// - key: symbol
// - value: symbol
// @param timeout {int}: Timeout (milliseconds) for querying.
// @param pipeline_name {symbol}: Name of pipeline to use for decoding a message. If transformer library is not used, this parameter is ignored.
// @return
// - int: Client index in `CLIENTS`.
.kafka.newConsumer:{[config;timeout;pipeline_name]
  consumer: .kafka.newClient["c"; config; timeout; pipeline_name];
  .kafka.startBackgroundPoll[consumer]
 };

// @kind function
// @category Create/Delete
// @brief Destroy client handle and remove from `CLIENTS`.
//  All registered callback for this client are removed.
// @param client_idx {int}: Index of client in `CLIENTS`.
// @note
// Replacement of `.kfk.ClientDel`. 
.kafka.deleteClient:{[client_idx]
  if[is_consumer: `c ~ .kafka.CLIENT_TYPE_MAP client_idx;
    // Consumer has not unsubscribed.
    if[count .kafka.getCurrentSubscription client_idx; .kafka.unsubscribe client_idx]
  ];

  // Stop polling
  .kafka.stopBackgroundPoll[client_idx];
  // Delete the client from kafka ecosystem.
  .kafka.deleteClient_impl[client_idx];

  if[not is_consumer;
    // Get topics of this producer
    topics: .kafka.PRODUCER_TOPIC_MAP client_idx;
    // Delete the producer from client-topic map
    .kafka.PRODUCER_TOPIC_MAP:client_idx _ .kafka.PRODUCER_TOPIC_MAP
  ];

  // Delete the client from client-type map
  .kafka.CLIENT_TYPE_MAP _: client_idx;

  // Delete error callback.
  .kafka.ERROR_CALLBACK_PER_CLIENT _: client_idx;

  // Delete throttle callback.
  .kafka.THROTTLE_CALLBACK_PER_CLIENT _: client_idx;
 };

//%% Pipeline %%//vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv/

// @brief Get a map from client indices to pipelines.
// @return q dictionary with client indices as keys and a pipeline names as values.
.kafka.getPipelinePerClient: LIBPATH_ (`get_pipeline_per_client; 1);

//%% Setting %%//vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv/

// @kind function
// @category Setting
// @brief Get a name of client from client index.
// @param client_index {int}: Index of client in `CLIENTS`.
// @return
// - symbol: handle name of the client denoted by the given index.
// @note
// Replacement of `.kfk.ClientName`
.kafka.getClientName:LIBPATH_ (`get_client_name; 1);

// @kind function
// @category Setting
// @brief Set log level for a given client.
// @param client_idx {int}: Index of client in `CLIENTS`.
// @param level {number}: Severity levels in syslog.
// @note 
// - For level setting, see https://en.wikipedia.org/wiki/Syslog#Severity_level
// - Replacement of `.kfk.SetLoggerLevel`.
.kafka.setLogLevel:LIBPATH_ (`set_log_level; 2);

//%% Miscellaneous %%//vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv/

// @kind function
// @category Miscellaneous
// @brief Return the current out queue length for a given client.
// @param client_idx {int}: Index of client in `CLIENTS`.
// @note
// - Only for debug. This function is called inside `.kafka.deleteClient` and exit timing internally.
// - Replacement of `.kfk.OutQLen`.
.kafka.getOutQueueLength:LIBPATH_ (`get_out_queue_length; 1);
