module MyLibrary
  # nasty static variable
  BigBallOfMud = { :woofed => 0 }
end

class Puppy
  def woof!
   # puts "woof! #{Thread.current}"
    # for book keeping
    MyLibrary::BigBallOfMud[:woofed] += 1
  end
end

pup = Puppy.new

# eventhough pup isn't static and is cute, woof! is still pretty nasty because
# it accesses a static variable.

100.times do
 Thread.new do
   pup.woof!
 end
end

sleep(1)
puts MyLibrary::BigBallOfMud[:woofed]

