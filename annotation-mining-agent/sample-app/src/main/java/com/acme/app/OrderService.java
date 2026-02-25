package com.acme.app;

import com.acme.eventing.EventTrigger;

@EventTrigger(topic = OrderEvents.TOPIC, eventType = "OrderCreated", version = 1, producer = "sample-app")
public class OrderService {

    @EventTrigger(topic = "orders.v1", eventType = "OrderCancelled", version = 2, description = "Emitted on cancel")
    public void cancelOrder(String orderId) {
        // ...
    }
}
