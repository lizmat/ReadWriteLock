# A simple test helper class to make testing lock behavior easier. the basic
# idea is that we go through a sequence of test steps with a few parallel
# threads, each thread doing some test action each step, and reporting some
# result. the function defining the test steps may elect to do nothing, or it
# may get blocked for one or more steps. after the test sequence is over, the
# collection of test step*thread results can be checked against some expectation
# this whole test setup is quite racy and depends on the test functions
# returning quickly, but I can't see how that could be avoided given the fact
# that they may be blocked, and therefore can't report when they are done
# reliably...
class LockTestSupport {
    # the array of functions that actually define the tests. they get called
    # each step in the sequence, with a reference to the LockTestSupport as a
    # param. they can then do whatever they think is necessary for the test, and
    # return a "trace" of what happened, e.g. a string. after the test, these
    # traces can be verified. the current time/clock can be determined through
    # the LockTestSupport ref, and care needs to be taken to always use this
    # rather than remembering the time, since we want to test blocking behavior.
    has @.testsubs;

    # through how many steps does the test run?
    has $.num-steps;

    # how long to sleep after each step [s]
    has $.delay = .1; 

    # this is not the lock under test, but required scaffolding to make
    # the threads under test go through their test sequence in lockstep
    has $!clock = 0;
    has $!lock = Lock.new();
    has $!cond = $!lock.condition();

    # run the actual test sequence, returns an 2D array of threads X steps with
    # the results reported by the test functions. if the test function does not
    # return in a given step, the array cells 'contains' an Any, which can be
    # tested again, the test function should always return something else to
    # make it easy to distinguish the case
    method run-sequence() {
        my @threads;
        my @result-set;
        for ^@!testsubs.elems -> $thread-num {
            @result-set.push([Any xx $!num-steps]);
            @threads.push(Thread.new(code => {
                my $wanted-step = 0;
                my $done = False;
                repeat {
                    $!lock.protect({
                        # first we want to wait for the next step in the
                        # sequence
                        while $!clock < $wanted-step {
                            $!cond.wait();
                        }
                    });

                    # now we can call the test function and collect the
                    # results
                    my $result = @!testsubs[$thread-num](self);

                    # when storing the result we evaluate the current time
                    # again, so that we store after the potential blocking
                    $!lock.protect({
                        @result-set[$thread-num][$!clock] = $result;
                        # determine the next step is the next after, which 
                        # could be larger than expected if we were blocked. 
                        # we also determine if we are done with the whole 
                        # sequence
                        $wanted-step++;
                        if $!clock > $wanted-step {
                            # we may have skipped some steps due to blocking
                            $wanted-step = $!clock + 1;
                        }
                        $done = $!clock >= $!num-steps - 1;
                    });
                } until ($done);

            }, :app_lifetime).run());
        }

        for ^$!num-steps {
            sleep $!delay;
            $!lock.protect({
                $!clock++;
            });
            $!cond.signal_all();
        }

        return @result-set;
    }

    method current-time() {
        $!lock.protect({
            return $!clock;
        });
    }
}

