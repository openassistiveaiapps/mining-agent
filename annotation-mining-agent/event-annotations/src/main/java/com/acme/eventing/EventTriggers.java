package com.acme.eventing;

import java.lang.annotation.*;

@Retention(RetentionPolicy.SOURCE)
@Target({ElementType.TYPE, ElementType.METHOD})
public @interface EventTriggers {
    EventTrigger[] value();
}
