//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//
//                    File Decription                    //
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//

// @file kafka_consumer.q
// @fileoverview
// Define kafka consumer interfaces.

//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//
//                    Public Interface                   //
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++//

//%% Configuration %%//vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv/

// @kind function
// @category Consumer
// @brief Get the broker-assigned group member ID of the client (consumer).
// @param consumer_idx {int}: Index of client (consumer) in `CLIENTS`.
// @return
// - symbol: Broker-assigned group member ID of the consumer.
// @note
// Replacement of `.kfk.ClientMemberId`
.kafka.getConsumerGroupMemberID:LIBPATH_ 	(`get_consumer_group_member_id; 1);

// @kind function
// @category Consumer
// @brief Get current subscription information for a consumer.
// @param consumer_idx {int}: Index of client (consumer) in `CLIENTS`.
// @return
// - list of dictionary: A list of topic-partition information dictionary.
// @note
// Replacement of `.kfk.Subscription`.
.kafka.getCurrentSubscription:LIBPATH_ (`get_current_subscription; 1);

//%% Consumer %%//vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv/

// @kind function
// @category Consumer
// @brief Subscribe to a given topic with its partitions (and offsets).
// @param consumer_idx {int}: Index of client (consumer) in `CLIENTS`.
// @param topic {symbol}: Topic to subscribe.
// @note
// Replacement of `.kfk.Sub`.
.kafka.subscribe_impl:LIBPATH_ (`subscribe; 2);

// @kind function
// @category Consumer
// @brief Make a given consumer unsubscribe.
// @param consumer_idx {int}: Index of client (consumer) in `CLIENTS`.
// @note
// Replacement of `.kfk.Unsub`.
.kafka.unsubscribe_impl:LIBPATH_ (`unsubscribe; 1);

.kafka.CONSUMER_SUBSCRIPTION:(`int$())!();

.kafka.subscribe:{[consumer_idx; topic]
  .kafka.subscribe_impl[consumer_idx; topic];
  // Add the new subscription to the map.
  .kafka.CONSUMER_SUBSCRIPTION[consumer_idx],: topic;
 }

.kafka.unsubscribe:{[consumer_idx]
  .kafka.CONSUMER_SUBSCRIPTION _: consumer_idx;
  .kafka.unsubscribe_impl[consumer_idx]
 }

.kafka.startConsume_impl: LIBPATH_ (`start_consume; 3);
.kafka.stopConsume_impl: LIBPATH_ (`stop_consume; 2);

.kafka.startConsume:{[consumer_idx;topic;partition;offset]
  topic_idx: .kafka.TOPICS topic;
  .kafka.startConsume_impl[topic_idx; partition; offset];
  .kafka.CONSUMER_SUBSCRIPTION[consumer_idx],: topic;
 }

.kafka.stopConsume:{[consumer_idx;topic;partition]
  topic_idx: .kafka.TOPICS topic;
  .kafka.stopConsume_impl[topic_idx; partition];
  .kafka.CONSUMER_SUBSCRIPTION[consumer_idx]: .kafka.CONSUMER_SUBSCRIPTION[consumer_idx] except topic;
 }
