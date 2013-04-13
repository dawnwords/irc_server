#! /usr/bin/env ruby
#
# 15-441 Simple IRC test
#
# You must have passed the previous tests.  For example, you cannot
# pass the "PART" test if your "JOIN" test failed.
# For this reason, the script exits once the server fails a test.
# If you fail a specific test, we suggest you modify this code
# to print out exactly # what is going on, or perhaps remove tests that
# fail so that you can test other, unrelated tests if you simply haven't
# implemented a particular bit of functionality yet (e.g., you might
# remove the WHO or LIST tests to test PART).
#
# Enjoy!
#
# - 15-441 Staff

## SKELETON STOLEN FROM http://www.bigbold.com/snippets/posts/show/1785
require 'socket'

$SERVER = "127.0.0.1"
$PORT = 22002  ########## DONT FORGET TO CHANGE THIS
$MODE = 1      ########## PROCESS MY TEST

class ModeError<Exception 
end

if ARGV.size == 0
  puts "Usage: ./simpleirc.rb server_port test_mode(0|1) [server_ip_addr]"
  exit
else
  begin
    $PORT = Integer(ARGV[0])  
    if ARGV.size == 2
      $MODE = Integer(ARGV[1])
    end
  rescue
    puts "The port & mode must be an integer!"
    exit
  end
end

if ARGV.size >= 3
  $SERVER = ARGV[2].to_s()
end


puts "Server address - " + $SERVER + ":" + $PORT.to_s()

class IRC

  def initialize(server, port, nick, channel)
    @server = server
    @port = port
    @nick = nick
    @channel = channel
  end

  def recv_data_from_server (timeout)
    pending_event = Time.now.to_i
    received_data = Array.new
    k = 0
    flag = 0
    while flag == 0
      ## check for timeout
      time_elapsed = Time.now.to_i - pending_event
      if (time_elapsed > timeout)
        flag = 1
      end
      ready = select([@irc], nil, nil, 0.0001)
      next if !ready
      for s in ready[0]
        if s == @irc then
          next if @irc.eof
          s = @irc.gets
          received_data[k] = s
          k= k + 1
        end
      end
    end
    return received_data
  end

  def test_silence(timeout)
    data=recv_data_from_server(timeout)
    if (data.size > 0)
      return false
    else
      return true
    end
  end

  def send(s)
    # Send a message to the irc server and print it to the screen
    puts "--> #{s}"
    @irc.send "#{s}\n", 0
  end

  def connect()
    # Connect to the IRC server
    @irc = TCPSocket.open(@server, @port)
  end

  def disconnect()
    @irc.close
  end

  def send_nick(s)
    send("NICK #{s}")
  end

  def send_user(s)
    send("USER #{s}")
  end

  def get_motd
    data = recv_data_from_server(1)
    ## CHECK data here

    if(data[0] =~ /^:[^ ]+ *375 *gnychis *:- *[^ ]+ *Message of the day - *.\n/)
      puts "\tRPL_MOTDSTART 375 correct"
    else
      puts "\tRPL_MOTDSTART 375 incorrect"
      return false
    end

    k = 1
    while ( k < data.size-1)

      if(data[k] =~ /:[^ ]+ *372 *gnychis *:- *.*/)
        puts "\tRPL_MOTD 372 correct"
      else
        puts "\tRPL_MOTD 372 incorrect"
        return false
      end
      k = k + 1
    end

    if(data[data.size-1] =~ /:[^ ]+ *376 *gnychis *:End of \/MOTD command/)
      puts "\tRPL_ENDOFMOTD 376 correct"
    else
      puts "\tRPL_ENDOFMOTD 376 incorrect"
      return false
    end

    return true
  end

  def send_privmsg(s1, s2)
    send("PRIVMSG #{s1} :#{s2}")
  end

  def raw_join_channel(joiner, channel)
    send("JOIN #{channel}")
    ignore_reply()
  end

  def join_channel(joiner, channel)
    send("JOIN #{channel}")

    data = recv_data_from_server(1);
    if(data[0] =~ /^:#{joiner}.*JOIN *#{channel}/)
      puts "\tJOIN echoed back"
    else
      puts "\tJOIN was not echoed back to the client"
      return false
    end

    if(data[1] =~ /^:[^ ]+ *353 *#{joiner} *= *#{channel} *:.*#{joiner}/)
      puts "\tRPL_NAMREPLY 353 correct"
    else
      puts "\tRPL_NAMREPLY 353 incorrect"
      return false
    end

    if(data[2] =~ /^:[^ ]+ *366 *#{joiner} *#{channel} *:End of \/NAMES list/)
      puts "\tRPL_ENDOFNAMES 366 correct"
    else
      puts "\tRPL_ENDOFNAMES 366 incorrect"
      return false
    end

    return true
  end

  def who(s)
    send("WHO #{s}")

    data = recv_data_from_server(1);

    if(data[0] =~ /^:[^ ]+ *352 *gnychis *#{s} *please *[^ ]+ *[^ ]+ *gnychis *H *:0 *The MOTD/)
      puts "\tRPL_WHOREPLY 352 correct"
    else
      puts "\tRPL_WHOREPLY 352 incorrect"
      return false
    end

    if(data[1] =~ /^:[^ ]+ *315 *gnychis *#{s} *:End of \/WHO list/)
      puts "\tRPL_ENDOFWHO 315 correct"
    else
      puts "\tRPL_ENDOFWHO 315 incorrect"
      return false
    end
    return true
  end

  def list
    send("LIST")

    data = recv_data_from_server(1);
    if(data[0] =~ /^:[^ ]+ *321 *gnychis *Channel *:Users Name/)
      puts "\tRPL_LISTSTART 321 correct"
    else
      puts "\tRPL_LISTSTART 321 incorrect"
      return false
    end

    if(data[1] =~ /^:[^ ]+ *322 *gnychis *#linux.*1/)
      puts "\tRPL_LIST 322 correct"
    else
      puts "\tRPL_LIST 322 incorrect"
      return false
    end

    if(data[2] =~ /^:[^ ]+ *323 *gnychis *:End of \/LIST/)
      puts "\tRPL_LISTEND 323 correct"
    else
      puts "\tRPL_LISTEND 323 incorrect"
      return false
    end

    return true
  end

  def checkmsg(from, to, msg)
    reply_matches(/^:#{from} *PRIVMSG *#{to} *:#{msg}/, "PRIVMSG")
  end

  def check2msg(from, to1, to2, msg)
    data = recv_data_from_server(1);
    if((data[0] =~ /^:#{from} *PRIVMSG *#{to1} *:#{msg}/ && data[1] =~ /^:#{from} *PRIVMSG *#{to2} *:#{msg}/) ||
       (data[1] =~ /^:#{from} *PRIVMSG *#{to1} *:#{msg}/ && data[0] =~ /^:#{from} *PRIVMSG *#{to2} *:#{msg}/))
       puts "\tPRIVMSG to #{to1} and #{to2} correct"
      return true
    else
      puts "\tPRIVMSG to #{to1} and #{to2} incorrect"
      return false
    end
  end

  def check_echojoin(from, channel)
    reply_matches(/^:#{from}.*JOIN *#{channel}/,
                  "Test if first client got join echo")
  end

  def part_channel(parter, channel)
    send("PART #{channel}")
    reply_matches(/^:#{parter}![^ ]+@[^ ]+ *QUIT *:/)

  end

  def check_part(parter, channel)
    reply_matches(/^:#{parter}![^ ]+@[^ ]+ *QUIT *:/)
  end

  def ignore_reply
    recv_data_from_server(1)
  end

  def reply_matches(rexp, explanation = nil)
    data = recv_data_from_server(1)
    if (rexp =~ data[0])
      puts "\t #{explanation} correct" if explanation
      return true
    else
      puts "\t #{explanation} incorrect: #{data[0]}" if explanation
      return false
    end
  end

end


##
# The main program.  Tests are listed below this point.  All tests
# should call the "result" function to report if they pass or fail.
##

$total_points = 0
$ta_score = 10
$my_case_num = 0
$my_case_pass = 0

def test_name(n)
  $my_case_num+=1
  puts "////// TC#{$my_case_num}: #{n} \\\\\\\\\\\\"  
  return n
end

def result(n, passed_exp, failed_exp, passed, points)
  explanation = nil
  if (passed)
    print "(+) #{n} passed"
    $total_points += points
    $my_case_pass += 1
    explanation = passed_exp
  else
    print "(-) #{n} failed"
    explanation = failed_exp
  end

  if (explanation)
    puts ": #{explanation}"
  else
    puts ""
  end
end

def eval_test(n, passed_exp, failed_exp, passed, points = 1)
  result(n, passed_exp, failed_exp, passed, points)
  exit(0) if !passed
end

irc = IRC.new($SERVER, $PORT, '', '')
irc2 = IRC.new($SERVER, $PORT, '', '')

begin

if($MODE == 0)
  irc.connect()
  ########## TEST NICK COMMAND ##########################
  # The RFC states that there is no response to a NICK command,
  # so we test for this.
  tn = test_name("NICK")
  irc.send_nick("gnychis")
  puts "<-- Testing for silence (5 seconds)..."

  eval_test(tn, nil, nil, irc.test_silence(5))


  ############## TEST USER COMMAND ##################
  # The RFC states that there is no response on a USER,
  # so we disconnect first (otherwise the full registration
  # of NICK+USER would give us an MOTD), then check
  # for silence
  tn = test_name("USER")

  puts "Disconnecting and reconnecting to IRC server\n"
  irc.disconnect()
  irc.connect()

  irc.send_user("please give me :The MOTD")
  puts "<-- Testing for silence (5 seconds)..."

  eval_test(tn, nil, "should not return a response on its own",
            irc.test_silence(5))

  ############# TEST FOR REGISTRATION ##############
  # A NICK+USER is a registration that triggers the
  # MOTD.  This test sends a nickname to complete the registration,
  # and then checks for the MOTD.
  tn = test_name("Registration")
  irc.send_nick("gnychis")
  puts "<-- Listening for MOTD...";

  eval_test(tn, nil, nil, irc.get_motd())

  ############## TEST JOINING ####################
  # We join a channel and make sure the client gets
  # his join echoed back (which comes first), then
  # gets a names list.
  tn = test_name("JOIN")
  eval_test(tn, nil, nil,
            irc.join_channel("gnychis", "#linux"))

  ############## WHO ####################
  # Who should list everyone in a channel
  # or everyone on the server.  We are only
  # checking WHO <channel>.
  # The response should follow the RFC.
  tn = test_name("WHO")
  eval_test(tn, nil, nil, irc.who("#linux"))

  ############## LIST ####################
  # LIST is used to check all the channels on a server.
  # The response should include #linux and its format should follow the RFC.
  tn = test_name("LIST")
  eval_test(tn, nil, nil, irc.list())

  ############## PRIVMSG ###################
  # Connect a second client that sends a message to the original client.
  # Test that the original client receives the message.
  tn = test_name("PRIVMSG")
  irc2.connect()
  irc2.send_user("please give me :The MOTD2")
  irc2.send_nick("gnychis2")
  msg = "clown hat curly hair smiley face"
  irc2.send_privmsg("gnychis", msg)
  eval_test(tn, nil, nil, irc.checkmsg("gnychis2", "gnychis", msg))

  ############## ECHO JOIN ###################
  # When another client joins a channel, all clients
  # in that channel should get :newuser JOIN #channel
  tn = test_name("ECHO ON JOIN")
  # "raw" means no testing of responses done
  irc2.raw_join_channel("gnychis2", "#linux")
  irc2.ignore_reply()
  eval_test(tn, nil, nil, irc.check_echojoin("gnychis2", "#linux"))


  ############## MULTI-TARGET PRIVMSG ###################
  # A client should be able to send a single message to
  # multiple targets, with ',' as a delimiter.
  # We use client2 to send a message to gnychis and #linux.
  # Both should receive the message.
  tn = test_name("MULTI-TARGET PRIVMSG")
  msg = "awesome blossom with extra awesome"
  irc2.send_privmsg("gnychis,#linux", msg)
  eval_test(tn, nil, nil, irc.check2msg("gnychis2", "gnychis", "#linux", msg))
  irc2.ignore_reply()

  ############## PART ###################
  # When a client parts a channel, a QUIT message
  # is sent to all clients in the channel, including
  # the client that is parting.
  tn = test_name("PART")
  eval_test("PART echo to self", nil, nil,
            irc2.part_channel("gnychis2", "#linux"),
            0) # note that this is a zero-point test!

  eval_test("PART echo to other clients", nil, nil,
            irc.check_part("gnychis2", "#linux"))

  # Your tests go here!
  
  # Things you might want to test:
  #  - Multiple clients in a channel
  #  - Abnormal messages of various sorts
  #  - Clients that misbehave/disconnect/etc.
  #  - Lots and lots of clients
  #  - Lots and lots of channel switching
  #  - etc.
  #
else
  irc3 = IRC.new($SERVER, $PORT, '', '')
  irc4 = IRC.new($SERVER, $PORT, '', '')

  puts("##################################################")
  puts("#     THIS IS THE BEGINNING OF MY TEST CASES     #")
  puts("##################################################")

  ############## Multiple Clients In A Channel ##############
  #  Test Command WHO,LIST,PRIVMSG,PART,QUIT
  nick1 = "nick1";
  nick2 = "nick2";
  nick3 = "nick3";
  nick4 = "nick4";

  channel1 = "&computer";
  channel2 = "#linux";

  ######################################
  #  TestCase: Register and Join 1
  tn = test_name("Register and Join 1")
  irc.connect()
  irc.send("NICK #{nick1}")
  irc.send("USER irc is so :great")
  irc.ignore_reply()
  irc.send("JOIN #{channel1}")
  data = irc.recv_data_from_server(1)
  eval_test(tn,nil,nil,
    (data[0] =~ /^:#{nick1} JOIN #{channel1}/ && 
      data[1] =~ /^:[^ ]+ 353 #{nick1} = #{channel1}:#{nick1}/ && 
      data[2] =~ /^:[^ ]+ 366 #{nick1} #{channel1} :End of \/NAMES list/))

  ######################################  
  #  TestCase: Register and Join 2
  tn = test_name("Register and Join 2")
  irc2.connect()
  irc2.send("NICK #{nick2}")
  irc2.send("USER I love irc :so Much")
  irc2.ignore_reply()
  irc2.send("JOIN #{channel1}")
  data = irc2.recv_data_from_server(1)
  eval_test(tn,nil,nil, (data[0] =~ /^:#{nick2} JOIN #{channel1}/ && 
      data[1] =~ /^:[^ ]+ 353 #{nick2} = #{channel1}:(#{nick1}|#{nick2})/ && 
      data[2] =~ /^:[^ ]+ 353 #{nick2} = #{channel1}:(#{nick1}|#{nick2})/ && 
      data[3] =~ /^:[^ ]+ 366 #{nick2} #{channel1} :End of \/NAMES list/))

  ######################################
  #  TestCase: 1 Echo After 2 Join
  tn = test_name("1 Echo After 2 Join")
  data = irc.recv_data_from_server(1)
  eval_test(tn,nil,nil,(data[0] =~ /^:#{nick2} JOIN #{channel1}/))

  ######################################
  #  TestCase: Register and Join 3
  tn = test_name("Register and Join 3")
  irc3.connect()
  irc3.send("NICK #{nick3}")
  irc3.send("USER finally the bug :is detected")
  irc3.ignore_reply()
  irc3.send("JOIN #{channel2}")
  data = irc3.recv_data_from_server(1)
  eval_test(tn,nil,nil,
    (data[0] =~ /^:#{nick3} JOIN #{channel2}/ && 
      data[1] =~ /^:[^ ]+ 353 #{nick3} = #{channel2}:#{nick3}/ && 
      data[2] =~ /^:[^ ]+ 366 #{nick3} #{channel2} :End of \/NAMES list/))

  ######################################
  #  TestCase: Register 4 and LIST
  tn = test_name("Register 4 and LIST")
  irc4.connect()
  irc4.send("NICK #{nick4}")
  irc4.send("USER finally the bug :is detected")
  irc4.ignore_reply()
  irc4.send("LIST")
  data = irc4.recv_data_from_server(1)
  eval_test(tn,nil,nil,
    (data[0] =~ /^:[^ ]+ 321 #{nick4} Channel :Users Name/ && 
      data[1] =~ /^:[^ ]+ 322 #{nick4} (#{channel1} 2|#{channel2} 1)/ && 
      data[2] =~ /^:[^ ]+ 322 #{nick4} (#{channel1} 2|#{channel2} 1)/ && 
      data[3] =~ /^:[^ ]+ 323 #{nick4} :End of \/LIST/))  

  ######################################
  #  TestCase: 4 Join Channel 2
  tn = test_name("4 Join Channel 2")
  irc4.send("JOIN #{channel2}")
  data = irc4.recv_data_from_server(1)
  eval_test(tn,nil,nil, (data[0] =~ /^:#{nick4} JOIN #{channel2}/ && 
      data[1] =~ /^:[^ ]+ 353 #{nick4} = #{channel2}:(#{nick3}|#{nick4})/ && 
      data[2] =~ /^:[^ ]+ 353 #{nick4} = #{channel2}:(#{nick3}|#{nick4})/ && 
      data[3] =~ /^:[^ ]+ 366 #{nick4} #{channel2} :End of \/NAMES list/))

  ######################################
  #  TestCase: 3 Echo After 4 Join
  tn = test_name("3 Echo After 4 Join")
  data = irc3.recv_data_from_server(1)
  eval_test(tn,nil,nil,(data[0] =~ /^:#{nick4} JOIN #{channel2}/))

  ######################################
  #  TestCase: PRIVMSG From 4 to 1 and Channel 2
  msg = "How is everything going tonight?"
  tn = test_name("4 PRIVMSG 1 And Channel 2")
  irc4.send("PRIVMSG #{nick1},#{channel2} :#{msg}")
  result = irc4.test_silence(2)
  result = result && irc2.test_silence(2)

  data = irc.recv_data_from_server(1)
  result = result && data[0] =~ /^:#{nick4} PRIVMSG #{nick1}:#{msg}/

  data = irc3.recv_data_from_server(1)
  result = result && data[0] =~ /^:#{nick4} PRIVMSG #{channel2}:#{msg}/
  eval_test(tn,nil,nil, result)

  ######################################
  #  TestCase: 4 Join Change Channel
  tn = test_name("4 Join Change Channel")
  irc4.send("JOIN #{channel1}")
  data = irc4.recv_data_from_server(1)
  eval_test(tn,nil,nil, (data[0] =~ /^:#{nick4}!finally@[^ ]+ QUIT:.+/ &&
      data[1] =~ /^:#{nick4} JOIN #{channel1}/ && 
      data[2] =~ /^:[^ ]+ 353 #{nick4} = #{channel1}:(#{nick2}|#{nick1}|#{nick4})/ && 
      data[3] =~ /^:[^ ]+ 353 #{nick4} = #{channel1}:(#{nick2}|#{nick1}|#{nick4})/ && 
      data[4] =~ /^:[^ ]+ 353 #{nick4} = #{channel1}:(#{nick2}|#{nick1}|#{nick4})/ && 
      data[5] =~ /^:[^ ]+ 366 #{nick4} #{channel1} :End of \/NAMES list/))

  ######################################
  #  TestCase: 1 Echo After 4 Join Change Channel
  tn = test_name("1 Echo After 4 Join Change Channel")
  data = irc.recv_data_from_server(1)
  eval_test(tn,nil,nil, data[0] =~ /^:#{nick4} JOIN #{channel1}/)

  ######################################
  #  TestCase: 2 Echo After 4 Join Change Channel
  tn = test_name("2 Echo After 4 Join Change Channel")
  data = irc2.recv_data_from_server(1)
  eval_test(tn,nil,nil, data[0] =~ /^:#{nick4} JOIN #{channel1}/) 

  ######################################
  #  TestCase: 3 Echo After 4 Join Change Channel
  tn = test_name("3 Echo After 4 Join Change Channel")
  data = irc3.recv_data_from_server(1)
  eval_test(tn,nil,nil, data[0] =~ /^:#{nick4}!finally@[^ ]+ QUIT:.+/) 

  ######################################
  #  TestCase: 3 WHO Channel 1
  tn = test_name("3 WHO Channel 1")
  irc3.send("WHO #{channel1}")
  data = irc3.recv_data_from_server(1)
  eval_test(tn,nil,nil,(data[3] =~ /^:[^ ]+ 315 #{nick3} *#{channel1} *:End of \/WHO list/ &&
    data[0] =~ /^:[^ ]+ 352 #{nick3} *#{channel1} *[^ ]+ *[^ ]+ *[^ ]+ *(#{nick1}|#{nick2}|#{nick4}) *H *:0.+/ &&
    data[1] =~ /^:[^ ]+ 352 #{nick3} *#{channel1} *[^ ]+ *[^ ]+ *[^ ]+ *(#{nick1}|#{nick2}|#{nick4}) *H *:0.+/ &&
    data[2] =~ /^:[^ ]+ 352 #{nick3} *#{channel1} *[^ ]+ *[^ ]+ *[^ ]+ *(#{nick1}|#{nick2}|#{nick4}) *H *:0.+/))
  
  ######################################
  #  TestCase: 2 WHO "finally"
  tn = test_name("2 WHO Channel 1")
  match = "finally"
  irc2.send("WHO #{match}")
  data = irc2.recv_data_from_server(1)
  eval_test(tn,nil,nil,(
    data[0] =~ /^:[^ ]+ 352 #{nick2} *(#{channel1}|#{channel2}) *[^ ]+ *[^ ]+ *[^ ]+ *(#{nick3}|#{nick4}) *H *:0.+/ &&
    data[1] =~ /^:[^ ]+ 352 #{nick2} *(#{channel1}|#{channel2}) *[^ ]+ *[^ ]+ *[^ ]+ *(#{nick3}|#{nick4}) *H *:0.+/ &&
    data[2] =~ /^:[^ ]+ 315 #{nick2} *#{match} *:End of \/WHO list/))
  

  ######################################
  #  TestCase: 2 PART Channel 1
  tn = test_name("2 PART Channel 1")
  irc2.send("PART #{channel1}")
  result = irc3.test_silence(2)
  data = irc2.recv_data_from_server(1)
  result = result && data[0] =~ /^:#{nick2}!I@[^ ]+ QUIT:.+/
  data = irc.recv_data_from_server(1)
  result = result && data[0] =~ /^:#{nick2}!I@[^ ]+ QUIT:.+/
  data = irc4.recv_data_from_server(1)
  result = result && data[0] =~ /^:#{nick2}!I@[^ ]+ QUIT:.+/
  eval_test(tn,nil,nil,result)

  ######################################
  #  TestCase: 1 QUIT
  tn = test_name("1 QUIT")
  irc.send("QUIT")
  irc.ignore_reply()  
  result = irc2.test_silence(2) 
  result = result && irc3.test_silence(2)
  result = result && irc4.reply_matches(/^:#{nick1}!irc@[^ ]+ QUIT:.+/) 
  eval_test(tn,nil,nil,result)

  ############## SEND MESSAGE TOO LONG ##############
  #  TestCase: 2 PRIVMSG 3 With Too Long Message
  tn = test_name("2 PRIVMSG 3 With Too Long Message")
  irc2.send(("NICK aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"+
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"+
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"+
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"+
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"+
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"+
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"+
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"+
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"+
    "aaaaaaaaaaaaaaaaaaaaaa"));
  eval_test(tn,nil,nil,irc2.reply_matches(/^.+:Erroneus nickname/))
  


  ############## ABNORMAL QUIT ##############
  #  TestCase: Client Disconnected
  tn = test_name("Client Disconnected")
  irc.disconnect()
  irc2.disconnect()
  irc3.disconnect() 
  irc4.disconnect()

  irc.connect()
  eval_test(tn,nil,nil,true)

  ############## NICK ABNORMAL MESSAGE ##############
  #  Test all abnormal input for NICK command  
  #  TestCase: Test NICK nothing
  tn = test_name("NICK nothing")
  irc.send("NICK")  
  eval_test(tn,nil,nil,irc.reply_matches(/^:No nickname given/,"NICK nothing return"))

  ######################################
  #  TestCase: Test NICK with illegal character  
  tn = test_name("NICK with illegal character")
  illegal = "@4%^*()"
  irc.send_nick(illegal)  
  eval_test(tn,nil,nil,irc.reply_matches(/^[^ ]+:Erroneus nickname/,"NICK illegal character return"))

  ######################################
  #  TestCase:  Test NICK with name longer than 9 characters
  tn = test_name("NICK with name longer than 9 characters")
  illegal = "aaaaaaaaaaaaaaaaa"
  irc.send_nick(illegal)  
  eval_test(tn,nil,nil,irc.reply_matches(/^[^ ]+:Erroneus nickname/,"NICK with name longer than 9 characters return"))
    
  ######################################
  #  TestCase:  Test NICK with name used already
  #  irc NICK with valid nick name
  tn = test_name("NICK with name used already")
  irc.send_nick("dawnwords")  
  irc.test_silence(2)

  #  irc2 NICK with the same nick name as irc  
  irc2.connect()
  irc2.send_nick("dawnwords")
  eval_test(tn,nil,nil,irc2.reply_matches(/^[^ ]+:Nickname is already in use/,"NICK with name used already return"))
  irc2.disconnect()

  ############## USER ABNORMAL MESSAGE ##############
  #  Test all abnormal input for USER command  
  #  TestCase: Test USER with arguments less than 4
  tn = test_name("USER with arguments less than 4")
  irc.send("USER need more sleep")
  eval_test(tn,nil,nil,irc.reply_matches(/^USER:Not enough parameters/,"USER with arguments less than 4 return"))

  ######################################
  #  TestCase: Test USER with arguments less than 4
  #  irc USER with valid infomation
  tn = test_name("USER twice with valid information ")
  irc.send("USER need more sleep :next week")
  irc.ignore_reply()

  #  irc USER twice with valid information
  irc.send("USER maybe just your :naive wish")
  eval_test(tn,nil,nil,irc.reply_matches(/^:You may not reregister/,"USER twice with valid information return"))
  
  ############## JOIN ABNORMAL MESSAGE ##############
  #  Test all abnormal input for JOIN command  
  #  TestCase: JOIN with no argument
  tn = test_name("JOIN with no argument")
  irc.send("JOIN")
  eval_test(tn,nil,nil,irc.reply_matches(/^JOIN *:Not enough parameters/,"JOIN with no argument return"))
  
  ######################################
  #  TestCase: JOIN with illegal name
  tn = test_name("JOIN with illegal name")
  irc.send("JOIN linux")
  eval_test(tn,nil,nil,irc.reply_matches(/^linux *:No such channel/,"JOIN with illegal argument return"))

  ######################################
  #  TestCase: JOIN twice with the same channel name
  tn = test_name("JOIN twice with the same channel name")
  #  JOIN correctly
  irc.send("JOIN &computer")
  irc.ignore_reply();

  #  JOIN the same channel
  irc.send("JOIN &computer")
  eval_test(tn,"JOIN twice with the same channel name stay silence(correct)\n","JOIN twice with the same channel name returns(inccorrect)\n",irc.test_silence(2))

  ############## WHO ABNORMAL MESSAGE ##############
  #  Test all abnormal input for WHO command
  #  TestCase: WHO with no argument
  tn = test_name("WHO with no argument")
  irc.send("WHO")
  eval_test(tn,nil,nil,irc.reply_matches(/^WHO *:Not enough parameters/,"WHO with no argument return"))


  ############## PRIVMSG ABNORMAL MESSAGE ##############
  #  Test all abnormal input for PRIVMSG command
  #  TestCase: PRIVMSG with no argument
  tn = test_name("PRIVMSG with no argument")
  irc.send("PRIVMSG")
  eval_test(tn,nil,nil,irc.reply_matches(/^:No recipient given PRIVMSG/,"PRIVMSG with no argument return"))

  ######################################
  #  TestCase: PRIVMSG with 1 argument
  tn = test_name("PRIVMSG with 1 argument")
  irc.send("PRIVMSG &computer")
  eval_test(tn,nil,nil,irc.reply_matches(/^:No text to send/,"PRIVMSG with 1 argument return"))  

  ######################################
  #  TestCase: PRIVMSG to self 
  tn = test_name("PRIVMSG to self")
  irc.send("PRIVMSG dawnwords :Hello world!")
  eval_test(tn,nil,nil,irc.test_silence(2))

  ######################################
  #  TestCase: PRIVMSG to 1 not existing user, 1 existing user
  #            1 not existing channel, 1 not exisiting channel
  tn = test_name("PRIVMSG to different targets")

  #  irc2 register and join channel &computer
  irc2.connect()
  irc2.send_nick("coder")
  irc2.send("USER maybe just your :naive wish")
  irc2.ignore_reply();
  irc2.send("JOIN &computer")
  irc2.ignore_reply();

  #  irc3 register only
  irc3 = IRC.new($SERVER, $PORT, '', '')
  irc3.connect()
  irc3.send_nick("farmer")
  irc3.send("USER you are just :a famer")
  irc3.ignore_reply();  


  irc.send("PRIVMSG farmer,tester,&computer,#linux :Hello world!")
  data = irc.recv_data_from_server(1)
  if data[0] =~ /^:coder JOIN &computer/ && data[1] =~ /^tester:No such nick\/channel/ && data[2] =~ /^#linux:No such nick\/channel/
    puts "irc receives correct"
  else
    puts "\t #{tn} fail:irc receives: #{data[0]} & #{data[1]}"
    exit  
  end
  
  data = irc2.recv_data_from_server(1)
  if data[0] =~ /^:dawnwords PRIVMSG &computer:Hello world!/
    puts "irc2 receives correct"
  else    
    puts "\t #{tn} fail:irc2 receives: #{data[0]}"
    exit
  end

  eval_test(tn,nil,nil,irc3.reply_matches(/^:dawnwords PRIVMSG farmer:Hello world!/,"irc3 receives"))


  ############## PART ABNORMAL MESSAGE ##############
  #  Test all abnormal input for PART command  
  #  TestCase: PART with no argument
  tn = test_name("PART with no argument")
  irc.send("PART")
  eval_test(tn,nil,nil,irc.reply_matches(/^PART *:Not enough parameters/,"PART with no argument return"))


  ######################################
  #  TestCase: PART channel not existing
  tn = test_name("PART channel not existing")
  irc.send("PART #linux")
  eval_test(tn,nil,nil,irc.reply_matches(/^[^ ]+ *:No such channel/,"PART channel not existing"))

  ######################################
  #  TestCase: PART channel not on
  tn = test_name("PART channel not on")

  irc3.join_channel("farmer","#linux")

  #  irc part #linux
  irc.send("PART #linux")
  eval_test(tn,nil,nil,irc.reply_matches(/^[^ ]+ *:You're not on that channel/,"You're not on that channel"))

  
  puts("##################################################")
  puts("#        THIS IS THE END OF MY TEST CASES        #")
  puts("##################################################")
end


rescue Interrupt
rescue Exception => detail
  puts detail.message()
  print detail.backtrace.join("\n")
ensure
  irc.disconnect()
  irc2.disconnect() 

  puts ""
  if $MODE == 0    
    puts "Your score: #{$total_points} / #{$ta_score}"
  else
    puts "PASS / TOTAL: #{$total_points} / #{$my_case_num}"
  end
  puts ""
  puts "Good luck with the rest of the project!"
end
