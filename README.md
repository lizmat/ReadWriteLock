[![Actions Status](https://github.com/lizmat/ReadWriteLock/workflows/test/badge.svg)](https://github.com/lizmat/ReadWriteLock/actions)

TITLE
=====

ReadWriteLock -- A lock with shared/exclusive access modes

SYNOPSIS
========

```raku
use ReadWriteLock;

my $l = ReadWriteLock.new;

my $thread-a = Thread.start({
    $l.lock-shared();
    for ^5 {
        sleep 1;
        say "thread A doing something under protection of the lock";
    }
    $l.unlock();
});

my $thread-b = Thread.start({
    $l.protect-shared({
        for ^5 {
            sleep 1;
            say "thread B doing something under protection of the lock";
        }
    });
});

my $thread-c = Thread.start({
    $l.protect-exclusive({
        for ^5 {
            sleep 1;
            say "thread C doing something under exclusive protection of the lock";
        }
    });
});

$thread-a.join;
$thread-b.join;
$thread-c.join;
```

FEATURES
========

  * Does what a basic `Lock` does, just slower and with more bugs ;)

  * Reentrant: the lock can be taken again by a thread that is already holding it It needs to be unlocked the same number of times it was locked before it can be taken by another thread

  * Fair in the sense of first-come-first-serve

  * Shared access: multiple 'readers' can share the lock, yet access is mutually exclusive between 'readers' and 'writers'

  * Lock Upgrade: you can upgrade a shared access mode to an exclusive without unlocking first, if no other thread is interferring. In this case you do not need to unlock twice.

PLANNED FEATURES
================

  * Read-for-write access mode that guarantees that a lock upgrade can be taken

  * Async version that returns threads to the threadpool and returns a promise from lock()

DESCRIPTION
===========

This module implements a lock/mutex with shared and exclusive access modes, so a set of 'readers' could share the lock while 'writers' need exclusive access. The lock is reentrant, so can be taken multiple times by the same thread, and fair in the sense of come-first-server-first. 

Please note that locks of whatever kind are a very low-level synchronisation mechanism and inherently difficult to use correctly, where possible higher-level mechanisms like a `Channel`, `Promise` or `Suppply` should be used.

EXAMPLES
========

Constructor
-----------

    use ReadWriteLock

    my $l = ReadWriteLock.new()

Constructing a ReadWriteLock is very simple and takes no arguments.

Protecting a Code segment
-------------------------

    $l.protect-shared({
        # code thunk
    });

    $l.protect-exclusive({
        # code thunk
    });

    $l.protect(shared, {
        # code thunk
    });

    $l.protect(exclusive, {
        # code thunk
    });

The `protect()` usage pattern has the distinct benefit that it automatically unlocks in case of e.g. exceptions or whenever the code block is being left. You can either use the 'long' form like `protect-shared()`, which is nice and implicit, or pass the access mode in as an argument, which allows determning it from a function and passing it around.

Direct locking/unlocking
------------------------

    $l.lock-shared();

    $l.lock-exclusive();

    $l.lock(shared);

    $l.lock(exclusive);

    $l.unlock();

Alternatively you can also use stand-alone lock/unlock calls, which allows tricky usages like overhand locking etc, but requires more care to be safe. If you lock multiple times, you need to unlock a matching number of times before the lock becomes available again.

Lock Upgrades
-------------

    $l.lock-shared();

    # do something

    $l.lock-exclusive();

    # do something else that requires exclusive access

    $l.unlock();

You can upgrade a lock that you are holding in shared mode to an exclusive access, as long as no other thread was traying to do the same before (You will get an exception in that case). In this case you only need to unlock once, the lock has been upgraded not re-entered.

AUTHORS
=======

Robert Lemmen (2018-2020), Elizabeth Mattijsen <liz@raku.rocks> (2021-)

Source can be located at: https://github.com/lizmat/ReadWriteLock . Comments and Pull Requests are welcome.

COPYRIGHT AND LICENSE
=====================

Copyright 2018-2020 Robert Lemmen, 2021 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

