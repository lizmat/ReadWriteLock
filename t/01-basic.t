use Test;

# XXX is this the best way to make test support classes available?
use lib 't/lib';
use LockTestSupport;

plan 1;

subtest 'Basic Lock operations should work as expected', {
    my $lock-under-test = Lock.new();
    my $lts = LockTestSupport.new(
        num-steps => 7,
        testsubs => [
            sub ($ltsr) {
                given $ltsr.current-time() {
                    when 1 {
                        $lock-under-test.lock();
                        return "L1";
                    }
                    when 2 {
                        $lock-under-test.lock();
                        return "L2";
                    }
                    when 3 {
                        $lock-under-test.unlock();
                        CATCH {
                            default: return "EX";
                        }
                        return "U3";
                    }
                    when 4 {
                        $lock-under-test.unlock();
                        return "U4";
                    }
                    default {
                        return "--";
                    }
                }
            },
            sub ($ltsr) {
                given $ltsr.current-time() {
                    when 0 {
                        CATCH {
                            default: return "EX";
                        }
                        $lock-under-test.unlock();
                        return "U0";
                    }
                    when 2 {
                        $lock-under-test.lock();
                        return "L2";
                    }
                    when 6 {
                        $lock-under-test.unlock();
                        return "U6";
                    }
                    default {
                        return "--";
                    }
                }
            },
        ]
    );

    plan 9;

    my $result = $lts.run-sequence();
    diag $result.gist;

    is $result[1][0], "EX", "attempting to unlock a lock we do not hold throws";

    is $result[0][1], "L1", "clean lock can be taken";
    is $result[0][2], "L2", "relocking accepted with lock already held";
    is $result[0][3], "U3", "unlocking works and returns";
    is $result[0][4], "U4", "unlocking again on lock taken twice does not throw";

    ok (!defined $result[1][2]), "attempting to lock an already taken lock blocks";
    ok (!defined $result[1][3]), "double-taken lock blocks other thread after first unlock";
    is $result[1][4], "L2", "blocked lock attempt suceeds after second unlock by other thread";
    is $result[1][6], "U6", "unlocking returns as expected";

    done-testing;
}

done-testing;
