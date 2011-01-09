class CheckSlony
  VERSION = '1.0.0'
end

requrie 'rubygems'
require 'pg'
require 'optparse'
require 'timeout'

pgoptions=''
pgtty=''
@result=''
@problems = 0 
@timeout = 10

OptionParser.new do |opt|
  opt.on("-H","--host=DBHOSTNAME", String, "Specify the DBHOSTNAME"){|h| @hostname = h }
  opt.on("-P","--port=PORTNUMBER", Integer, "Specify the DB port number"){|p| @port = p }
  opt.on("-u","--username=DBUSER", String, "Specify the DB user name"){|u| @user = u }
  opt.on("-d","--dbname=DBNAME", String, "Specify the DB  name"){|d| @dbname = d }
  opt.on("-p","--password=PASSWORD", String, "Specify the DB password"){|p| @password = p }
  opt.on("-C","--cluster=CLUSTERNAME", String, "Specify the DB CLUSTER NAME"){|c| @cluster = c }
  opt.on("-e","--events=EVENTS", Integer, "Specify the Event Counts"){|e| @event = e }
  opt.on("-l","--lagtime=LAGTIME", Integer, "Specify the LAGTIME"){|l| @lagtime = l }
  opt.on("-t","--timeout=TIMEOUT", Integer, "Specify the TIMEOUT"){|t| @timeout = t }

  begin
    opt.parse!(ARGV)
  rescue OptionParser::ParseError => err
    $stderr.puts err.message
    $stderr.puts opt.help
  end
end

begin 
  timeout(@timeout){
    # sleep 3 # for debug
    con = PGconn.new(@hostname, @port, pgoptions, pgtty, @dbname, @user, @password) 
    query = 'SELECT st_origin, st_received, st_lag_num_events, round(extract(epoch from st_lag_time)) from "_' + @cluster + '".sl_status'

    res = con.exec(query)
    unless res
      print "POSTGRES_REPLICATION_LAG CRITICAL: Cannot prepare $DBI::errstr\n";
      exit 2
    end

    res.each do |r|

      node = r["st_received"]
      master = r["st_origin"]
      lag = r["st_lag_num_events"]
      round = r["round"]

      @result += "SUBSCRIBER " + node  + " ON ORIGIN " + master + " : EVENT LAG=" +  lag
      if (lag.to_i > 0) && (@event < lag.to_i)
      	 @result = @result + " (BEHIND " + (lag.to_i - @event).to_s + ") ";
      	 @problems += 1
      end
      @result = @result + " TIME LAG=" + round + "s";
      
      if (@lagtime > 0) && (@lagtime < round.to_i)
	 @result = @result + " (BEHIND " + (round.to_i - @lagtime).to_s + "s) ";
	 @problems += 1
      end
      @result = @result + " || ";

    end

    if @problems > 0
      @result = "POSTGRES_REPLICATION_LAG CRITICAL: " + @result + "\n"
      print @result
      exit 2
    else 
      @result = "POSTGRES_REPLICATION_LAG OK: " + @result + "\n"
      print @result
      exit 0
    end
    
    print $problems;
    con.close
  }
  
rescue Timeout::Error => ex
  print "POSTGRES_REPLICATION_LAG TIMEOUT: #{ex.message}";
  exit 3
rescue => ex
  print "POSTGRES_REPLICATION_LAG UNKNOWN: #{ex.message}";
  exit 3
end

exit;
