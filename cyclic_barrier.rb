require 'java'

java_import 'java.util.concurrent.Semaphore'



SEM = Semaphore.new(10)


class Gouauld
  def say_work!
    puts "Human, kree!"
    sleep(1)
    SEM.release
  end
end

class Human
  def build_pyramid
    puts "Yes, master"
    SEM.acquire
    sleep(2)
  end
end

4.times do
  Thread.new do
    g = Gouauld.new
    loop { g.say_work! }
  end
end

10.times do
  Thread.new do
    h = Human.new
    loop { h.build_pyramid }
  end
end


sleep 100
