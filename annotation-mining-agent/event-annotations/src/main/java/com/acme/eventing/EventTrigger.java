package com.acme.eventing;

import java.lang.annotation.*;

@Retention(RetentionPolicy.SOURCE)
@Target({ElementType.TYPE, ElementType.METHOD})
@Repeatable(EventTriggers.class)
public @interface EventTrigger {
    String topic();
    String eventType();
    int version() default 1;

    // Optional fields (nice for metadata and reporting)
    String producer() default "";
    String description() default "";
}
