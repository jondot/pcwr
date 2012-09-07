# Pragmatic Concurrency With Ruby


I'm coming from a parallel computation, distributed systems background by education, and have relatively strong foundations in infrastructural concurrent/parallel libraries and products that I've built and maintained over the years, on both the JVM and .NET.

Recently, I've dedicated more and more time building and deploying real concurrent projects with Ruby using [JRuby](http://jruby.org), as opposed to developing with Ruby (MRI) with concurrency the way it is (process-level and GIL thread-level). I'd like to share some of that with you.


_Administrative note<<EOF_:

> This may come as a lengthy information-packed read.
You can put the blame on me for this one, because I wanted to increase the value for the reader as much as possible, and pack something that could have been a lengthy book, into a single highly concentrated no-bullshit article.

> As an experiment, I also put most of the example code in a repository including the source of this article. Please feel free to fork and apply contributions of any kind, I'll gladly accept pull requests.

> Github repo: [https://github.com/jondot/pcwr](https://github.com/jondot/pcwr)

_EOF_


## Concurrency is Awesome!

Remember those [old 8-bit games](http://en.wikipedia.org/wiki/Double_Dragon) you used to play as a child?. In a hindsight - you know its awesome, but if you're a gamer or just a casual gamer, and you're forced to play it today, the graphics will feel bad.

This is because it’s a detail thing; just like childhood computer games, as time passes, it seems like your brain doesn't care (or forgets) the proper details.

So given that one is an MRI Ruby developer, her mindset would be that concurrency just works, and it is easy and awesome. But you might be right guessing that due to the level of cynicism going around here - it isn't the end of it.

The MRI Ruby [GIL](http://en.wikipedia.org/wiki/Global_Interpreter_Lock) is gracefully keeping some details away from you: yes things _are_ running in parallel with the help of _properly_ built I/O libraries (for example: historically, the MySQL gem was initially not doing it properly, which meant your thread would block on I/O), but surely, __code__ isn't running in parallel. It's just like what your brain did when it covered up for those horrific 8-bit graphics that you were sure are still awesome.


<!-- more -->


For real concurrency that isn't [soft padded by the GIL](http://www.igvita.com/2008/11/13/concurrency-is-a-myth-in-ruby/)? if you're not armed with the proper mental and practical tools, there's a good chance you'll quickly find yourself in front of nasty [race conditions](http://en.wikipedia.org/wiki/Race_condition). The human mind only goes so much in order to reason about parallel events.

And when you're stuck rummaging through tons of stack traces from memory dumps you just took off production? you'll have to [CSI](http://en.wikipedia.org/wiki/CSI:_Crime_Scene_Investigation) yourself out of the situation, at which point I bet you'll beg to have a single process, 0-concurrency thing running instead.

MRI Ruby helps you. It can __guarantee__ that you don't have real concurrency, at the price of not running code in a really parallel way.


And that's fine. But today, lets walk through real concurrency so that you'll have the proper intuition and background when you need to break out of these
limitations.

## Why?

Several years ago, I worked on an enterprise-grade software in the [DFM](http://en.wikipedia.org/wiki/Design_for_manufacturability_(PCB) / electronics field at Mentor Graphics. There was one product, which was able to optimize the kind of [machines](http://en.wikipedia.org/wiki/SMT_placement_equipment) that fabricate the components of the phones, laptops and electronics that you use day to day and all aspects of their manufacturing operation, so that they were used to the maximum possible capacity. It did so by modeling the manufacturing pipeline in ways that humans never could.

In this field, a machine not working at its 100% capacity is directly translated to money lost. And worse, if a bug in the optimizing software caused a few hours of downtime, that's plain catastrophic.

By an analogy, CPUs were made to burn cycles. If you have a machine that doesn't work all of its cores, all on 100% CPU and in the first place you _need_ more
performance out of your application, then concurrency is one of the solutions.

The world is heading towards a [distributed](http://hadoop.apache.org/) and [concurrent](http://akka.io/) processing model, that would allow squeezing every bit of juice out of machines, using any number of machines.

A great starting point is to allow your _Ruby_ code to utilize all that it can within the framework of itself, and by that, to be in a better position to take part in this move as well.


## State of The Union

Having a shared state, visible to everyone, and without a way of telling who's using it, is _insane_. It's more insane when you throw in several threads to mutate it.


Putting Ruby aside for a moment, one of the most agonizing things for me when reviewing Java or .Net code, is to see a developer using static variables.

If you haven't yet the chance to use a statically typed language like Java or C#, then the term _static_ is used in the sense that there is one instance of the thing, well defined as 'static' by the hosting language,
and is visible _implicitly_, i.e. no one is explicitly declaring it in any interface, or explicitly passing it to other objects (as a simplistic example: a global variable).


Since these languages are statically typed, there's always a feeling that its OK to [prematurely optimize](http://c2.com/cgi/wiki?PrematureOptimization) bits,
because we're on a statically typed language and performance is _always_ expected of us; we should always be on guard. This creates a reality where developers often prematurely optimize things.



Back to Ruby. Going through popular frameworks and gems, I can't but admit that Ruby has grown to
be 'static happy'. But I think its for an entirely different reason -- which is: threads were never there to challenge the concept of
using and mutating global state.

In Ruby, that one static always-visible container, often sneaks out. In a hindsight you'll note that some times
it simply serves as a poor man's Inversion-of-Control (“IoC”) - and that's cool; other times, it is misused as a big ball of mud, often mutated all along the running code by many different parts of your applications. In any case, on real concurrent platforms such as JRuby its still plain dangerous.

That's why even on MRI, I cringe every time I have to use a static variable in the framework/library
I'm basing my code on, and every time I'm using an object that _I know_ will use a static variable,
because as you might already know, that shit is transitive:

```ruby
module MyLibrary
  # nasty static variable
  BigBallOfMud = { :woofed => 0 }
end

class Puppy
  def woof!
    puts "woof!"
    # for book keeping
    MyLibrary::BigBallOfMud[:woofed] += 1
  end
end

pup = Puppy.new

# eventhough pup isn't static and is cute, woof! is still pretty nasty because
# it accesses a static variable.
pup.woof!
```

How dangerous is it? look:

```ruby
100.times do
 Thread.new do
   pup.woof!
 end
end

sleep(5)
puts MyLibrary::BigBallOfMud[:woofed]
```

I have removed the `puts` from `woof!` in order to position thread contention in a better way, and running it on JRuby gives:

```
$ ruby test.rb
97
```

And the result varies from run to run due to the timing of your threads. MRI Ruby on the other hand correctly and reliably produces `100`, you guessed it - because of the GIL.


Problem is, I have the feeling that everyone _around me_ are in a non-concurrent world, and are accustomed to keeping and using (sharing) global static variables while never flipping that "what if another thread gets here" switch that kills everyone's party.







## Thread Safety

The first step into the concurrent world, is to use a real concurrent platform, for us Rubyists, it is indisputably JRuby. Not to mention, the JVM is still _very_ strong, and really great for server-side work.

The next step is to care and worry about _thread safety_. If you're using a 3rd party ruby gem, or a Java library, you should be aware that there's a chance it is not thread safe, and once more than one of your threads hit it at the same time it'll blow up, and just to further emphasize on the previous discussion - wouldn't have blown up if your code was running on MRI.

Sure, you can blow things up with Ruby threads; doing shared I/O for example but this is besides the point for now: I'm talking about code running in parallel, mutating shared state.

Lets take a look at this simplistic statistics metrics server written in Sinatra.

```ruby
require 'sinatra'
require 'json'


class StatsApp < Sinatra::Base
  configure :production, :development do
    set :stats, {}
    puts "configured app"
  end

  post '/stats/:product/:metric' do
    settings.stats[params[:product]] ||= {}
    settings.stats[params[:product]][params[:metric]] ||= 0
    settings.stats[params[:product]][params[:metric]] += 1
    "ok"
  end

  get '/stats/:product' do
    settings.stats[params[:product]].to_json
  end
end
```

Note that we idiomatically initialize null references when we encounter a new `metric` and a new `product`. Let’s run it with MRI and `thin`:

```
$ ab -n 20000 -c 100 -p /dev/null http://localhost:9292/stats/foo/mongodb.read
  ... snip ...
  Complete requests:      20000
  ... snip ...
  Requests per second:    683.95 [#/sec] (mean)
  ... snip ...
```

And now:

```
$ curl http://localhost:9292/stats/foo
   {"mongodb.read":200}
```


Not bad for a low-resource VM. Lets switch to JRuby and `trinidad`, which is a an embedded tomcat servlet container. If you're running this on your box, note that I've warmed up the JVM first so that JITing will get us nicer performance numbers (you can too by running around a couple 10K requests first):

```
# after running 80K requests in chunks of 20K, the last batch
# produces this number (which is more than MRI with thin - yay JVM)
Requests per second:    1011.42 [#/sec] (mean)

$ curl http://localhost:9292/stats/foo
  {"mongodb.read":72506}
```
We're missing around 7500 data points. What happened?

Two things happened:

* We probably lost a great deal of a chunk when the metric was first initialized; this is due to the fact that when one thread was busy initializing that globally shared hash, a few more were running over and overwriting its hash with one of their own.
* Another thing is non-atomic increments to the same cell, as shown previously with the puppy hash example.

So we saw an example of a service that could be real and useful (to a degree), using two very real application servers that behave differently under different platforms.


### A New Reality


In which you always ask: _is this thing I'm using thread-safe?_

* Ensuring that ruby itself is thread safe (things like constructing objects via `new`, for example). This is guaranteed for you within JRuby, by the JRuby team.

* Ensuring that 3rd party libraries are thread safe. This you'll have to find out by yourself, although most major web frameworks and gems are thread safe already by now. I personally like to double-check by going over the code.

* Ensuring that database drivers, infrastructural libraries, and libraries that often end up implemented in C (in our case, most probably Java), are thread safe. Again, you'll have to read the detail on the tin.

* Ensuring that your application server is blissfully threaded (running each request in a thread, etc). Typically Java servlet containers are great, one example would be [Trinidad](http://thinkincode.net/trinidad/), additionally, Ruby-built servers like [Puma](http://puma.io/) should be great as well. Here is a [comprehensive list](https://github.com/jruby/jruby/wiki/Servers).

* Ensuring that your web framework is thread safe (Sinatra and Rails are, just to name a couple)

* Ensuring that your code is thread safe. That's the easy part, since it's all on you.

* Be mindful of the number of cores your machine has. Level of true parallelism your code has is bound to the number of cores you have. One core isn't going to do much for you, and numerous cores will expose different non-deterministic behavior as you should expect.


This list might seem long and frightening, but it really isn't once you realize a couple of things about the code you're going to use:

### 3rd Parties
Most of the uncertainty you might be getting at, would come from 3rd party gems and libraries. Here, you can take a bite at a pretty awesome low-hanging fruit - Java/JRuby interop. Since the Java world has been living and breathing threads for years now, I often give considerable time for evaluating Java libraries in place of Ruby gems for better concurrency support (examples below).

Here is a common infrastructural concern: logging.

What I need is the usual with logging levels and filtering, it should also have log outputters of the kinds I'd need now and what I might need in the future, behave nice with highly concurrent applications, etc.

**Example: Log4r and (Java's) Logback**

The one I'm looking at which comes as close as possible as such all-encompassing framwork is [log4r](https://github.com/colbygk/log4r).
Since I know this goes into a JRuby backed system, I swiftly move to locate its concurrency points, and land on [this](https://github.com/colbygk/log4r/commit/8f43dc049df1a5ec430c57630b4bbd56b7dd29f9).

Great, and I do prefer having pure ruby here to keep things familiar for other developers. Eventually, I move on with the integration, just to find out the [GELF](http://graylog2.org/) outputter I was using doesn't like concurrency much - I'm getting crashes and stack traces all over the place, something to do with the JRuby `UDPSocket` initialization.

I [move on to fix it in my fork](https://github.com/jondot/gelf-rb) but in the same thread of thought I grab [Logback](http://logback.qos.ch/) (the now rising logging framework for Java) from the back of my head and ponder about replacing log4r completely with it.

```ruby
# Gemfile

# drop the soup of gems that used to do this.
#gem 'log4r'
#gem 'gelf', :git => 'git://github.com/jondot/gelf-rb.git'
#gem 'log4r-gelf'

# credit to rjack for wrapping up logback for jruby
gem 'rjack-logback'
```


I then grab the [GELF outputter jar](https://github.com/Moocar/logback-gelf) and place it in a `/jars` folder.

Setting it up is a concoction of Ruby and JRuby/Java interop:

```ruby
# set up logback
require 'rjack-logback'
require 'java'
require 'jars/logback-gelf-0.9.6p1-jar-with-dependencies.jar'

RJack::Logback.configure do
  RJack::Logback.load_xml_config(File.expand_path('config/logback.xml', File.dirname(__FILE__)))
end
logger = RJack::SLF4J[ "main.logger" ]
```

Where `logback.xml` is a quite harmless XML, representing the [logging configuration](http://logback.qos.ch/manual/configuration.html), just what you might know from Log4r or Log4j.

Finishing up with a solution that I liked better. Yes it’s a hybrid solution, but I feel it can be trusted in a [highly concurrent](http://logback.qos.ch/reasonsToSwitch.html) environment.



### Your Own
Next up would be _your own_ code.

For orchestrating concurrency, Ruby is primarily giving you a `Mutex`. In high-performance concurrency terms, that's not such a great find, and will cause contention problems for your threads (out of the scope of this discussion).

For these specific situations, _should you ever come into them_, you should go non-blocking with the native Java  [concurrent primitives and collections](http://docs.oracle.com/javase/1.5.0/docs/api/java/util/concurrent/package-summary.html), again Java/JRuby interop for the rescue.

**Mutex**

A great, and more importantly real-world example of `Mutex` and Ruby in the wild is [in Celluloid](https://github.com/celluloid/celluloid/blob/master/lib/celluloid/mailbox.rb#L17).

Celluloid models concurrency in a unique way. Like Erlang, and Akka on the JVM, there are several constructs or patterns that
enable building fault-tolerant and concurrent applications. These are definitely eye-openers, but for the sake of focus, let's simplify.

You can look at Celluloid as a framework that enables you to build a network of "agents", that communicate through _message passing_. For
that to work properly, you can imagine that every agent sits on its own thread, and every agent has its own mailbox.

Since many agents (threads) can message any number of other agents, or specifically many agents can message a single agent, concurrency becomes an issue. How
can you guarantee messages are accepted in the receiving agent properly with no one stepping on each other's foot.

More specifically, how can you _guarantee_ that [the mailbox](https://github.com/celluloid/celluloid/blob/master/lib/celluloid/mailbox.rb), which would probably be based on some kind of list, be _thread safe_ ?

```ruby
# https://github.com/celluloid/celluloid/blob/master/lib/celluloid/mailbox.rb#L23
#
# Add a message to the Mailbox
def <<(message)
  @mutex.lock
  begin
    if message.is_a?(SystemEvent)
      # Silently swallow system events sent to dead actors
      return if @dead
.. more code with mutex scattered around ..
```

Here we see some usage of `mutex`. So the answer is, everywhere you want to create a _[critical section](http://en.wikipedia.org/wiki/Critical_section)_ which is where only one thread would be allowed to run, is where you would wrap a `mutex` over.

And the great thing is that this kind of code works in real, production systems. And if you're on the lets-reduce-memory-for-background-jobs bandwagon, you're probably already using it implicitly, with [Sidekiq](https://github.com/mperham/sidekiq).



Now, let’s move towards the lower-hanging fruit.


I mentioned that I often like to review existing Java (or JVM, be it scala, clojure, what have you) libraries, because I feel that their concurrency
story is more mature and it may be more suitable for the task.

Lets start off with the very recent Celluloid example, where `mutex` is used. It seems that `mutex` and friends are used to create a thread safe queue,
which is one of the basic things you would find several variants of in Java.

**Concurrent Queues**

Here's [one non-blocking implementation](http://docs.oracle.com/javase/1.5.0/docs/api/java/util/concurrent/ConcurrentLinkedQueue.html) of a concurrent thread safe queue, that if you're up for it, you can interop with in your JRuby code.

If you're feeling lost about the 'non-blocking' terminology, in general, a _non-blocking_ variant of a thread-safe data structure is mostly favored over the lock/monitor/mutex implementations because it presents a fine-grained locking model that reduces contention.

```ruby
require 'java'

java_import 'java.util.concurrent.ConcurrentLinkedQueue'

q = ConcurrentLinkedQueue.new

i = 0
300.times do
  q.add i
  i += 1
end

puts q
```

But hold your horses now, Ruby offers a thread-safe queue out of the box in the `thread` library; feel free to use that if you feel a bit awkward interoping with Java in this way. Use ConcurrentLinkedQueue if you have the performance requirements for it.



**Atomic**

On every platforms, there are semantic for atomicity. Our x86 CPUs contain constructs called _[registers](http://en.wikipedia.org/wiki/Processor_register)_, and these are a certain bits wide. Often you'll see a 64bits CPU, which means its registers are also 64bits wide among other things.

This creates a situation, where it may be that assigning a 64bit wide number on a 32bit CPU (with matching 32bit wide registers) may _not_ be atomic, so in simple things like this:

```ruby
i = 42
j = i
```

Assigning `j=i` may be a 2 part operation, with space between its parts for other threads to sneak in and ruin the party, when running this code with many threads.

To solve this some platforms or languages _guarantee_ that assigning reference types is atomic, no matter the underlying CPU architecture. They also have guarantees regarding value types.

However, we can not care about this and guarantee atomicity in Ruby with [Atomic](https://github.com/headius/ruby-atomic) by JRuby lead Charles Nutter (@headius) himself:

```ruby
my_atomic = Atomic.new(42)
my_atomic.update {|v| v + 1}
```

Don't forget that this is a fully fledged data structure, and you'll have to _ask_ for the new value with

```ruby
my_atomic.value
```

The cool thing about this and other JRuby libraries in general, is that if you take a look [under the hood](https://github.com/headius/ruby-atomic/blob/master/ext/org/jruby/ext/atomic/AtomicReferenceLibrary.java), you'll see that it relies in its core on Java's own `AtomicReferenceFieldUpdater`, awesome!.




# Concurrency Primitives in a Hurry

So we just reviewed a Mutex, a concurrent queue, Atomic, and more. If you're like me, by now you can't stop yourself by asking, are there other constructs I can use?

Well the answer is a definite yes. Here's a quick review.



## Immutability

The first rule for concurrency zen is: to stop mutating state, make it immutable. Give other threads, or even functions a _copy_ of what you have instead of a reference to
what you have. This way any modification isn't any of your concern because _your_ data remain confidentially yours.

If you really want to, you can optimize memory with [Copy on Write](http://en.wikipedia.org/wiki/Copy-on-write) which basically says you don't really
need a copy unless you want to do something to it (like change it). You can use Java's own `CopyOnWriteArrayList` as an example.

When you do, we'll arrange a copy on the fly - but until then, for all of your readings
you'll use the original.

In this context, [message passing](http://en.wikipedia.org/wiki/Message_passing) must be mentioned. However, I think I would be a great injustice to it if I attempt to explain it and its history in a sub-sub section. Feel free to explore it, because it's a very important subject for concurrency in general, and there _is_ a [Ruby relative / ancestor](http://en.wikipedia.org/wiki/Smalltalk) strongly based on it after all.


## Semaphore

A [semaphore](http://en.wikipedia.org/wiki/Semaphore_(programming)) is one of the most versatile constructs that you will encounter.

Each semaphore can hold a number `N`. A thread can signal that it has
_acquired_ on a semaphore and once it does, the semaphore value is decreased from `N` to `N-1` atomically.

Once the semaphore run out, the thread will wait on it. However, any thread at any time can _release_ on a semaphore, thereby increasing the semaphore value from `N` to `N+1` atomically.

A semaphore is so useful, that among the rest, the trivial example is that you can model a Mutex with it: simply a semaphore with `N=1`.

It should be noted that in these things, based on where you're coming from (education, platform), the actions of manipulating a semaphore may have different naming but the same semantics: wait/signal, put/take, inc/dec, or acquire/release. This is also true for other constructs.



For the matter of demonstrating, I'll show how a semaphore can be used.

From a code structure and quality point of view, this is just throw-away back-of-napkin code, so don't take any of this seriously as a proper design -- just notice the ideas.

Here's a simple [Stargate SG-1](http://en.wikipedia.org/wiki/Stargate_SG-1) inspired classic [producer-consumer](http://en.wikipedia.org/wiki/Producer-consumer_problem) model:

```ruby
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
```

Resulting in an imbalanced producer-consumer relationship ([Jaffa](http://en.wikipedia.org/wiki/Goa'uld)s not keeping the pace with humans)

```
Human, kree!
Human, kree!
Human, kree!
Yes, masterYes, master
Yes, master

Yes, master
Yes, master
Yes, master
Yes, master
Yes, master
Yes, master
Yes, master
Human, kree!
```



## Countdown Latch

This is very similar to a real life latch in its behavior, just that you can set a number which is counted down on. Every thread can signal that it is done its intended work by counting down on the latch once. When it hits the latch it will be forced to wait on it. Once all required threads hit the latch, and it is fully counted down, everyone (all threads) is set free at once.

A unique property of the latch is that it is one-time one-use. Once the latch is open, you can't reset it.

A synchronization aid that allows one or more threads to wait until a set of operations being performed in other threads completes.

```ruby
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
```

By the way, my use of `sleep(X)` to wait for all threads isn't that encouraged in real code. In your real code, you should [`Thread.join`](http://www.ruby-doc.org/core-1.9.3/Thread.html#method-i-join) to enforce waiting for other threads.

```
[1347019958]#<Thread:0x4c0ce83d> boo!
[1347019958]#<Thread:0x636323cc> boo!
[1347019958]#<Thread:0x1c3590e> boo!
[1347019958]#<Thread:0x400ba709> boo!
```


## Cyclic Barrier

A barrier is similar in its behavior to the latch, only that you can reset it. It may be also called Rendezvous on other platforms or languages, just so you
have a better reference.

There are many more, but I'll leave the rest to you, I guess you get the drift.

```ruby
require 'java'

java_import 'java.util.concurrent.CyclicBarrier'

barrier = CyclicBarrier.new(4);

puts "kill me with CTRL-C"

loop do
  4.times do
    Thread.new do
      sleep rand(3)
      barrier.await
      puts "[#{Time.now.to_i}]#{Thread.current} Come on... what are you waiting for? kill me!"
    end
  end
  sleep(5)
end
```

As with the countdown latch, this example lends itself to be very similar (except the [Predator](http://www.imdb.com/title/tt0093773/) reference :), but now we can re-enter this barrier as many times as we want.

The output clearly shows that all threads are in concert, every time they pass the barrier.

```
kill me with CTRL-C
[1347020546]#<Thread:0x53635a08> Come on... what are you waiting for? kill me!
[1347020546]#<Thread:0x3dea1661> Come on... what are you waiting for? kill me!
[1347020546]#<Thread:0x1fabedfd> Come on... what are you waiting for? kill me!
[1347020546]#<Thread:0x50958d49> Come on... what are you waiting for? kill me!
[1347020552]#<Thread:0x929750e> Come on... what are you waiting for? kill me!
[1347020552]#<Thread:0x6e4a084c> Come on... what are you waiting for? kill me!
[1347020552]#<Thread:0x65639ad4> Come on... what are you waiting for? kill me!
[1347020552]#<Thread:0x6ed4b575> Come on... what are you waiting for? kill me!
^C
```
# Wait a Minute

But here's something to think about. Do you really want _real_ concurrency?

The truth is, you can _still_ do quite a lot of work in the work loads we're handling in startups, enterprises, and web in general. This is primarily due to the
fact that most of your work is I/O-bound.

You make a database query, munge the data, generate output and stream it to clients. Much of this is I/O, and given that I/O is several orders of
magnitude slower than memory operations (code), MRI Ruby has quite a bit of time to allocate to other threads.

Or you make a one or more Web API requests, get the data, save to database, and stream it to clients. Again _tons_ of I/O.

This is why MRI Ruby will still serve you well into which ever task you have in hand in this domain. But, you will _absolutely_ need real concurrency
if you hit a performance plateau and by then, you'll probably be an expert in this field.


But hey! you'll never get to experience the JVM with JRuby as your language of choice, and its _really_ great [so try it out](http://jruby.org/).

