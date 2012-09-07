
require 'java'

java_import 'java.util.concurrent.CountDownLatch'

latch = CountDownLatch.new(4);


4.times do
  Thread.new do
    sleep rand(3)
    latch.count_down
    latch.await
    puts "[#{Time.now.to_i}]#{Thread.current} boo!"
  end
end

sleep(5)
