//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//
//                     Load Libraries                    //
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//

#include <kafkakdb_utility.h>
#include <kafkakdb_topic.h>
#include <kafkakdb_client.h>

//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//
//                    Global Variables                   //
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//

/**
 * @brief Topic names expressed in symbol list
 */
K TOPICS = 0;

//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//
//                   Private Functions                   //
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//

/**
 * @brief Set topic configuration in q dictionary on kafka topic configuration object.
 * @param tpc_conf: Destination kafka topic configuration object
 * @param q_tpc_config: Source q topic configuration dictionary (symbol -> symbol).
 * @return 
 * - error (nullptr): Failure
 * - empty list: Success
 */
static K load_topic_config(rd_kafka_topic_conf_t *tpc_conf, K q_tpc_config){
  // Buffer for error message
  char error_message[512];
  for(J i= 0; i < kK(q_tpc_config)[0]->n; ++i){
    if(RD_KAFKA_CONF_OK !=rd_kafka_topic_conf_set(tpc_conf, kS(kK(q_tpc_config)[0])[i], kS(kK(q_tpc_config)[1])[i], error_message, sizeof(error_message)))
      return krr((S) error_message);
  }
  // Arbitrary value `()` other than nullptr so that caller of this function can tell error(`krr`) and success
  return knk(0);
}

/**
 * @brief Retrieve topic object by topic index
 * @param index: Index of topic
 * @return 
 * - symbol: Topic
 * - error if index is out of range or topic for the index is null
 */
rd_kafka_topic_t *index_to_topic_handle(K topic_idx){
  if(((UI) topic_idx->i < TOPICS->n) && kS(TOPICS)[topic_idx->i]){
    // Valid topic index.
    // Return topic object.
    return (rd_kafka_topic_t *) kS(TOPICS)[topic_idx->i];
  }else{
    // Index out of range or unregistered topic index.
    // Return error.
    char error_message[32];
    sprintf(error_message, "unknown topic: %di", topic_idx->i);
    return (rd_kafka_topic_t *) krr(error_message);
  }
}

//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//
//                      Interface                        //
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//

/**
 * @brief Create a new topic.
 * @param client_idx: index of client in `CLIENTS`.
 * @param topic: New topic to create.
 * @param q_config: q dictionary storing configuration of the new topic (symbol -> symbol).
 * @return 
 * - int: Topic handle assigned by kafka.
 */
EXP K new_topic(K client_idx, K topic, K q_config){

  if(!check_qtype("is!", client_idx, topic, q_config)){
    // Argument types do not match expected types
    return krr((S) "client index, topic and configuration must be (int; symbol; dictionary)");
  }

  rd_kafka_t *handle=index_to_handle(client_idx);
  if(!handle){
    // Null pointer (`krr`). Error in `index_to_handle()`.
    return (K) handle;
  }

  // Holder of kafka configuration object
  rd_kafka_topic_conf_t *config= rd_kafka_topic_conf_new();
  // Load configuration from q configuration object to the holder
  load_topic_config(config, q_config);

  rd_kafka_topic_t *new_topic = rd_kafka_topic_new(handle, topic->s, config);

  // Store topic index
  // Why symbol rather than int?
  int idx=0;
  while(idx!=TOPICS->n){
    if(kS(TOPICS)[idx] == 0){
      // Reuse 0 hole
      kS(TOPICS)[idx]=ss((S) new_topic);
      // Return topic handle as int
      return ki(idx);
    }
    ++idx;
  }

  // There was no 0 hole
  // Append new one to the tail
  js(&TOPICS, (S) new_topic);
  // Return topic handle as int
  return ki(idx);
}

/**
 * @brief Delete the given topic from kafka broker.
 * @param topic_idx: Index of topic in `TOPICS`.
 */
EXP K delete_topic(K topic_idx){
  
  if(!check_qtype("i", topic_idx)){
    // topic index is not int
    return krr("topic index must be int type.");
  }

  rd_kafka_topic_t *topic_handle=index_to_topic_handle(topic_idx);
  if(!topic_handle){
    // Nul pointer (`krr`). Error happened in `index_to_topic_handle()`.
    return (K) topic_handle;
  }

  // Delete topic
  rd_kafka_topic_destroy(topic_handle);

  // Fill the hole with 0.
  // This hole must be resused.
  kS(TOPICS)[topic_idx->i]= (S) 0;

  return KNULL;
}

/**
 * @brief Get a name of topic from topic index.
 * @param topic_idx: Index of topic in `TOPICS`.
 * @return 
 * - symbol: Topic name.
 */
EXP K get_topic_name(K topic_idx){

  if(!check_qtype("i", topic_idx)){
    // topic index is not int
    return krr("topic index must be int type.");
  }

  rd_kafka_topic_t *topic_handle=index_to_topic_handle(topic_idx);
  if(!topic_handle){
    // Null pointer `krr`. Error happened in `index_to_topic_handle()`.
    return (K) topic_handle;
  }
  
  // Return topic name from the handle
  return ks((S) rd_kafka_topic_name(topic_handle));
}
