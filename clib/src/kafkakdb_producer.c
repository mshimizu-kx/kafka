//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//
//                     Load Libraries                    //
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//

#include <string.h>
#include <stdlib.h>
#include <kafkakdb_utility.h>
#include <kafkakdb_topic.h>
#include <kafkakdb_client.h>
#ifdef USE_TRANSFORMER
#include <qtfm.h>
#endif

//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//
//                      Interface                        //
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//


/**
 * @brief Flush a handle of a producer.
 * @param producer_idx: Index of a client (producer) in `CLIENTS`.
 * @param q_timeout: Timeout (milliseconds) for waiting for flush.
 */
EXP K flush_producer_handle(K producer_idx, K q_timeout){
  
  if(!check_qtype("i[hij]", producer_idx, q_timeout)){
    // Error in type check.
    return krr((S) "producer_idx and q_timeout must be (int; short|int|long) type.");
  }

  rd_kafka_t *handle=index_to_handle(producer_idx);
  if(!handle){
    // Null pointer (`krr`). Error in `index_to_handle()`.
    return (K) handle;
  }

  I timeout=0;
  switch(q_timeout->t){
    case -KH:
      timeout=q_timeout->h;
      break;
    case -KI:
      timeout=q_timeout->i;
      break;
    default:
      timeout=q_timeout->j;
      break;
  }

  // Flush the handle of the producer
  rd_kafka_resp_err_t error= rd_kafka_flush(handle, timeout);
  if(error!=KFK_OK){
    // Timeout
    return krr((S) rd_kafka_err2str(error));
  }
    
  return KNULL;
 }

// Support only if rdkafka version >= 0.11.4
#if (RD_KAFKA_VERSION >= 0x000b04ff)

/**
 * @brief Publish message with custom headers.
 * @param producer_idx: Index of client (producer) in `CLIENTS`.
 * @param topic_idx: Index of topic in `TOPICS`.
 * @param partition: Topic partition.
 * @param payload: Payload to be sent.
 * @param key: Message key.
 * @param headers: Message headers expressed in a map between header keys to header values (symbol -> string).
 */
EXP K publish_with_headers(K producer_idx, K topic_idx, K partition, K payload, K key, K headers){
  
  if(!check_qtype("iii[CG]!", producer_idx, topic_idx, partition, key, headers)){
    // Error in check type.
    return krr((S) "producer_idx, topic_idx, partition, payload, key and headers must be (int; int; int; string; dictionary) type.");
  }
    
  rd_kafka_t *handle=index_to_handle(producer_idx);
  if(!handle){
    // Null pointer (`krr`). Error in `index_to_handle()`.
    return (K) handle;
  }
    
  rd_kafka_topic_t *topic_handle=index_to_topic_handle(topic_idx);
  if(!topic_handle){
    // Null pointer (`krr`). Error in `index_to_topic_handle()`.
    return (K) topic_handle;
  }
    
  K hdr_keys = (kK(headers)[0]);
  K hdr_values = (kK(headers)[1]);

  // Type check of headers
  if (hdr_keys->t != KS || hdr_values->t != 0){
    // headers contain wrong type
    return krr((S) "header keys and header values must be (list of symbol; compound list) type.");
  }
  for(int idx=0; idx < hdr_values->n; ++idx){
    K hdrval = kK(hdr_values)[idx];
    if (hdrval->t != KG && hdrval->t != KC){
      // Header value is not string
      return krr((S) "header value must be string or byte list type.");
    }
  }

  rd_kafka_headers_t* message_headers = rd_kafka_headers_new((int) hdr_keys->n);
  for (int idx=0; idx < hdr_keys->n; ++idx){
    K hdrval = kK(hdr_values)[idx];
    // Add a pair of header key and value to headers
    rd_kafka_header_add(message_headers, kS(hdr_keys)[idx], -1, kG(hdrval), hdrval->n);
  }

#ifdef USE_TRANSFORMER

  // Use pipeline to encode payload
  K pipeline_name=ks(kS(CLIENT_PIPELINES)[producer_idx->i]);
  payload=transform(pipeline_name, payload);
  if(!payload){
    // Error happenned in transformation
    r0(pipeline_name);
    return payload;
  }
  // Delete pipeline_name no longer necessary
  r0(pipeline_name);

#endif

  rd_kafka_resp_err_t err = rd_kafka_producev(
                        handle,
                        RD_KAFKA_V_RKT(topic_handle),
                        RD_KAFKA_V_PARTITION(partition->i),
                        RD_KAFKA_V_MSGFLAGS(RD_KAFKA_MSG_F_COPY),
                        RD_KAFKA_V_VALUE(kG(payload), payload->n),
                        RD_KAFKA_V_KEY(kG(key), key->n),
                        RD_KAFKA_V_HEADERS(message_headers),
                        RD_KAFKA_V_END);
  if(err!=KFK_OK){
    // Error in sending message
    return krr((S) rd_kafka_err2str(err));
  }
    
  return KNULL;
}

// rdkafka version < 0.11.4
#else

EXP K publish_with_headers(K UNUSED(client_idx), K UNUSED(topic_idx), K UNUSED(partition), K UNUSED(value), K UNUSED(key), K UNUSED(headers)) {
  return krr(".kafka.PublishWithHeaders is not supported for current rdkafka version. please update to librdkafka >= 0.11.4");
}

#endif

/**
 * @brief Send a message with a specified topic to a specified partition.
 * @param producer_idx: Index of client (producer) in `CLIENTS`.
 * @param topic_idx: Index of topic in `TOPICS`.
 * @param partition: Topic partition.
 * @param payload: Message to send.
 * @key: Message key. `""` for auto-generated key.
 */
EXP K publish(K producer_idx, K topic_idx, K partition, K payload, K key){
  
  // No longer check type of a payload.
  if(!check_qtype("iii[CG]", producer_idx, topic_idx, partition, key)){
    // Wrong argument types
    return krr((S) "producer index, topic index, partition and key must be (int; int; int; string; string) type.");
  }
    
  rd_kafka_topic_t *topic_handle=index_to_topic_handle(topic_idx);
  if(!topic_handle){
    // Null pointer (`krr`). Error in `index_to_topic_handle()`.
    return (K) topic_handle;
  }
  
#ifdef USE_TRANSFORMER

  // Use pipeline to encode payload
  K pipeline_name=ks(kS(CLIENT_PIPELINES)[producer_idx->i]);
  payload=transform(pipeline_name, payload);
  if(!payload){
    // Error happenned in transformation
    r0(pipeline_name);
    return payload;
  }
  k(0, "{show x}", r1(payload), KNULL);
  // Delete pipeline_name no longer necessary
  r0(pipeline_name);
  
#endif

  if(rd_kafka_produce(topic_handle, partition->i, RD_KAFKA_MSG_F_COPY, kG(payload), payload->n, kG(key), key->n, NULL)){
    // Error in sending a message
    return krr((S) rd_kafka_err2str(rd_kafka_last_error()));
  }
    
  return KNULL;
}

// Ony support for rdkafka ver. >= 0.11.4
#if (RD_KAFKA_VERSION >= 0x000b04ff)

/**
 * @brief Send messages with a specified topic to single or multiple partitions.
 * @param topic_idx: Index of topic in `TOPICS`.
 * @param partitions: 
 * - int: Partition to use for all message
 * - list of ints: Partition per message 
 * @param payloads: List of messages.
 * @param keys: 
 * - `""`: Use auto-generated key for all messages
 * - list of string: Keys for each message
 * @return 
 * - list of symbol: Error for each published message.
 * @note
 * https://github.com/edenhill/librdkafka/blob/master/src/rdkafka.h (rd_kafka_resp_err_t)
 */
EXP K publish_batch(K producer_idx, K topic_idx, K partitions, K payloads, K keys){
  
  // No longer check type of a payload.
  if(!check_qtype("ii[iI][CG*]", producer_idx, topic_idx, partitions, keys)){
    // Wrong argumrent types
    return krr((S) "producer index, topic index, partitions, payloads and keys must be (int; int; int|list of int; list of string; null or list of string) type.");
  }
    
  int num_messages = payloads->n;
  if ((keys->t == 0) && (num_messages != keys->n)){
    // Key was specified to each message but the number of messages does not match the number of keys
    return krr((S) "length of keys does not match the length of payloads");
  }

  if((partitions->t == KI) && (num_messages != partitions->n)){
    // Partitionwas secified to each message but the number of partitions does not match the number of  messages
    return krr((S) "length of partitions does not match the length of payoads");
  }
  
  // Type check for each key
  for(int i = 0 ; i < num_messages ; i++){
      
    if((keys->t ==0) && (kK(keys)[i]->t != KG) && (kK(keys)[i]->t !=KC)){
      // Key is neither of string nor bytes
      return krr((S) "key must be string type.");
    }

  }

  rd_kafka_topic_t *topic_handle=index_to_topic_handle(topic_idx);
  if(!topic_handle){
    // Null pointer (`krr`). Error in `index_to_topic_handle()`.
    return (K) topic_handle;
  }
    
  int default_partition = RD_KAFKA_PARTITION_UA;
  int message_flags = RD_KAFKA_MSG_F_COPY;
  if (partitions->t == KI){
    // Partition was specified to each message
    message_flags |= RD_KAFKA_MSG_F_PARTITION;
  }
  else{
    // Single partition was specified
    default_partition = partitions->i;
  }
  
  rd_kafka_message_t *messages;
  // Reserve a space for `num_messages` of messages
  messages = calloc(sizeof(*messages), num_messages);

#ifdef USE_TRANSFORMER

  K pipeline_name=ks(kS(CLIENT_PIPELINES)[producer_idx -> i]);
  
#endif

  for(int i = 0 ; i < num_messages ; i++){
    
    K payload = kK(payloads)[i];

#ifdef USE_TRANSFORMER
  
    // Use pipeline to encode payload
    payload=transform(pipeline_name, payload);
    if(!payload){
      // Error happenned in transformation
      r0(pipeline_name);
      return payload;
    }

#endif

    K key;
    if (keys->t == 0){
      // Key was specified to each message
      key = kK(keys)[i];
    }
    else{
      // Empty key was specified. Use auto-generated key.
      key=keys;
    }
    
    // Build message struct
    messages[i].payload = kG(payload);
    messages[i].len = payload->n;
    messages[i].key = kG(key);
    messages[i].key_len = key->n;
    messages[i].partition = kI(partitions)[i]; 

  }

#ifdef USE_TRANSFORMER

  // Delete pipeline_name no longer necessary
  r0(pipeline_name);

#endif

  // Send a batch of messages
  rd_kafka_produce_batch(topic_handle, default_partition, message_flags, messages, num_messages);

  // Collect error messages if any
  K results = ktn(KS, num_messages);
  for (int i = 0 ; i < num_messages ; i++){
    // Do not return error to release allocated memory
    // Store error if `err` is not equal to `KFK_OK`
    kS(results)[i]=(KFK_OK!=messages[i].err)? (S) rd_kafka_err2str(messages[i].err): "";
  }
  
  // Release the memory allocated by `calloc`.
  // `rd_kafka_message_destroy` cannot be used due to `calloc`.
  free(messages);

  return results;
}

// rdkafka version < 0.11.4
#else

EXP K publish_batch(K UNUSED(topic_idx), K UNUSED(partitions), K UNUSED(payloads), K UNUSED(keys)){
  return krr(".kafka.publishBatch is not supported for current rdkafka version. please update to librdkafka >= 0.11.4");
}

#endif
