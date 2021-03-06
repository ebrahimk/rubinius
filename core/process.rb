module Process
  def self.time
    Rubinius.primitive :vm_time
    raise PrimitiveFailure, "Process.time primitive failed"
  end

  def self.cpu_times
    Rubinius.primitive :vm_times
    raise PrimitiveFailure, "Process.cpu_times primitive failed"
  end

  ##
  # Sets the process title. Calling this method does not affect the value of
  # `$0` as per MRI behaviour. This method returns the title set.
  #
  # @param [String] title
  # @return [Title]
  #
  def self.setproctitle(title)
    val = Rubinius::Type.coerce_to(title, String, :to_str)

    Rubinius.invoke_primitive(:vm_set_process_title, val)
  end

  def self.setrlimit(resource, cur_limit, max_limit=undefined)
    resource =  coerce_rlimit_resource(resource)
    cur_limit = Rubinius::Type.coerce_to cur_limit, Integer, :to_int

    unless undefined.equal? max_limit
      max_limit = Rubinius::Type.coerce_to max_limit, Integer, :to_int
    end

    rlimit = Rlimit.new
    rlimit[:rlim_cur] = cur_limit
    rlimit[:rlim_max] = undefined.equal?(max_limit) ? cur_limit : max_limit

    ret = FFI::Platform::POSIX.setrlimit(resource, rlimit.pointer)
    Errno.handle if ret == -1
    nil
  end

  def self.getrlimit(resource)
    resource = coerce_rlimit_resource(resource)

    lim_max = []
    rlimit = Rlimit.new
    ret = FFI::Platform::POSIX.getrlimit(resource, rlimit.pointer)
    Errno.handle if ret == -1

    [rlimit[:rlim_cur], rlimit[:rlim_max]]
  end

  def self.setsid
    pgid = FFI::Platform::POSIX.setsid
    Errno.handle if pgid == -1
    pgid
  end

  def self.fork
    pid = Rubinius::Mirror::Process.fork

    if block_given? and pid.nil?
      begin
        yield nil
        status = 0
      rescue SystemExit => e
        status = e.status
      rescue Exception => e
        e.render "An exception occurred in a forked block"
        status = 1
      end

      until Rubinius::AtExit.empty?
        begin
          Rubinius::AtExit.shift.call
        rescue SystemExit => e
          status = e.status
        end
      end

      # Do not use Kernel.exit. This raises a SystemExit exception, which
      # will run ensure blocks. This is not what MRI does and causes bugs
      # in programs. See issue http://github.com/rubinius/rubinius/issues#issue/289 for
      # an example

      Kernel.exit! status
    end
    pid
  end

  def self.times
    Struct::Tms.new(*cpu_times)
  end

  def self.kill(signal, *pids)
    raise ArgumentError, "PID argument required" if pids.length == 0

    use_process_group = false
    signal = signal.to_s if signal.kind_of?(Symbol)

    if signal.kind_of?(String)
      if signal[0] == ?-
        signal = signal[1..-1]
        use_process_group = true
      end

      if signal[0..2] == "SIG"
        signal = signal[3..-1]
      end

      signal = Signal::Names[signal]
    end

    raise ArgumentError unless signal.kind_of? Fixnum

    if signal < 0
      signal = -signal
      use_process_group = true
    end

    pids.each do |pid|
      pid = Rubinius::Type.coerce_to_pid pid

      pid = -pid if use_process_group
      result = FFI::Platform::POSIX.kill(pid, signal)

      Errno.handle if result == -1
    end

    return pids.length
  end

  def self.abort(msg=nil)
    if msg
      msg = StringValue(msg)
      $stderr.puts(msg)
    end
    raise SystemExit.new(1, msg)
  end

  def self.getpgid(pid)
    pid = Rubinius::Type.coerce_to pid, Integer, :to_int

    ret = FFI::Platform::POSIX.getpgid(pid)
    Errno.handle if ret == -1
    ret
  end

  def self.setpgid(pid, int)
    pid = Rubinius::Type.coerce_to pid, Integer, :to_int
    int = Rubinius::Type.coerce_to int, Integer, :to_int

    ret = FFI::Platform::POSIX.setpgid(pid, int)
    Errno.handle if ret == -1
    ret
  end

  @maxgroups = 32
  class << self
    attr_reader :maxgroups
    def maxgroups=(m)
      @maxgroups = m
    end
  end

  def self.setpgrp
    setpgid(0, 0)
  end
  def self.getpgrp
    ret = FFI::Platform::POSIX.getpgrp
    Errno.handle if ret == -1
    ret
  end

  def self.pid
    ret = FFI::Platform::POSIX.getpid
    Errno.handle if ret == -1
    ret
  end

  def self.ppid
    ret = FFI::Platform::POSIX.getppid
    Errno.handle if ret == -1
    ret
  end

  def self.uid=(uid)
    # the 4 rescue clauses below are needed
    # until respond_to? can be used to query the implementation of methods attached via FFI
    # atm respond_to returns true if a method is attached but not implemented on the platform
    uid = Rubinius::Type.coerce_to uid, Integer, :to_int
    begin
      ret = FFI::Platform::POSIX.setresuid(uid, -1, -1)
    rescue NotImplementedError
      begin
        ret = FFI::Platform::POSIX.setreuid(uid, -1)
      rescue NotImplementedError
        begin
          ret = FFI::Platform::POSIX.setruid(uid)
        rescue NotImplementedError
          if Process.euid == uid
            ret = FFI::Platform::POSIX.setuid(uid)
          else
            raise NotImplementedError
          end
        end
      end
    end

    Errno.handle if ret == -1

    uid
  end

  def self.gid=(gid)
    gid = Rubinius::Type.coerce_to gid, Integer, :to_int
    Process::Sys.setgid gid
  end

  def self.euid=(uid)
    # the 4 rescue clauses below are needed
    # until respond_to? can be used to query the implementation of methods attached via FFI
    # atm respond_to returns true if a method is attached but not implemented on the platform
    uid = Rubinius::Type.coerce_to uid, Integer, :to_int
    begin
      ret = FFI::Platform::POSIX.setresuid(-1, uid, -1)
    rescue NotImplementedError
      begin
        ret = FFI::Platform::POSIX.setreuid(-1, uid)
      rescue NotImplementedError
        begin
          ret = FFI::Platform::POSIX.seteuid(uid)
        rescue NotImplementedError
          if Process.uid == uid
            ret = FFI::Platform::POSIX.setuid(uid)
          else
            raise NotImplementedError
          end
        end
      end
    end

    Errno.handle if ret == -1

    uid
  end

  def self.egid=(gid)
    gid = Rubinius::Type.coerce_to gid, Integer, :to_int
    Process::Sys.setegid gid
  end

  def self.uid
    ret = FFI::Platform::POSIX.getuid
    Errno.handle if ret == -1
    ret
  end

  def self.gid
    ret = FFI::Platform::POSIX.getgid
    Errno.handle if ret == -1
    ret
  end

  def self.euid
    ret = FFI::Platform::POSIX.geteuid
    Errno.handle if ret == -1
    ret
  end

  def self.egid
    ret = FFI::Platform::POSIX.getegid
    Errno.handle if ret == -1
    ret
  end

  def self.getpriority(kind, id)
    kind = Rubinius::Type.coerce_to kind, Integer, :to_int
    id =   Rubinius::Type.coerce_to id, Integer, :to_int

    FFI::Platform::POSIX.errno = 0
    ret = FFI::Platform::POSIX.getpriority(kind, id)
    Errno.handle
    ret
  end

  def self.setpriority(kind, id, priority)
    kind = Rubinius::Type.coerce_to kind, Integer, :to_int
    id =   Rubinius::Type.coerce_to id, Integer, :to_int
    priority = Rubinius::Type.coerce_to priority, Integer, :to_int

    ret = FFI::Platform::POSIX.setpriority(kind, id, priority)
    Errno.handle if ret == -1
    ret
  end

  def self.groups
    g = []
    count = Rubinius::FFI::Platform::POSIX.getgroups(0, nil)
    FFI::MemoryPointer.new(:int, count) { |p|
      num_groups = FFI::Platform::POSIX.getgroups(count, p)
      Errno.handle if num_groups == -1
      g = p.read_array_of_int(num_groups)
    }
    g
  end

  def self.groups=(g)
    @maxgroups = g.length if g.length > @maxgroups
    FFI::MemoryPointer.new(:int, @maxgroups) { |p|
      p.write_array_of_int(g)
      Errno.handle if FFI::Platform::POSIX.setgroups(g.length, p) == -1
    }
    g
  end

  def self.initgroups(username, gid)
    username = StringValue(username)
    gid = Rubinius::Type.coerce_to gid, Integer, :to_int

    if FFI::Platform::POSIX.initgroups(username, gid) == -1
      Errno.handle
    end

    Process.groups
  end

  #
  # Wait for the given process to exit.
  #
  # The pid may be the specific pid of some previously forked
  # process, or -1 to indicate to watch for *any* child process
  # exiting. Other options, such as process groups, may be available
  # depending on the system.
  #
  # With no arguments the default is to block waiting for any
  # child processes (pid -1.)
  #
  # The flag may be Process::WNOHANG, which indicates that
  # the child should only be quickly checked. If it has not
  # exited yet, nil is returned immediately instead.
  #
  # The return value is the exited pid or nil if Process::WNOHANG
  # was used and the child had not yet exited.
  #
  # If the pid has exited, the global $? is set to a Process::Status
  # object representing the exit status (and possibly other info) of
  # the child.
  #
  # If there exists no such pid (e.g. never forked or already
  # waited for), or no children at all, Errno::ECHILD is raised.
  #
  # TODO: Support other options such as WUNTRACED? --rue
  #
  def self.wait2(input_pid=-1, flags=nil)
    input_pid = Rubinius::Type.coerce_to input_pid, Integer, :to_int

    if flags and (flags & WNOHANG) == WNOHANG
      value = Rubinius.invoke_primitive :vm_waitpid, input_pid, true
      return if value.nil?
    else
      value = Rubinius.invoke_primitive :vm_waitpid, input_pid, false
    end

    if value == false
      raise Errno::ECHILD, "No child process: #{input_pid}"
    end

    # vm_waitpid returns a tuple when wait needs to communicate the pid that
    # was actually detected as stopped (since wait can wait for all child
    # pids, groups, etc)
    status, termsig, stopsig, pid = value

    status = Process::Status.new(pid, status, termsig, stopsig)
    Rubinius::Mirror::Process.set_status_global status

    [pid, status]
  end

  #
  # Wait for all child processes.
  #
  # Blocks until all child processes have exited, and returns
  # an Array of [pid, Process::Status] results, one for each
  # child.
  #
  # Be mindful of the effects of creating new processes while
  # .waitall has been called (usually in a different thread.)
  # The .waitall call does not in any way check that it is only
  # waiting for children that existed at the time it was called.
  #
  def self.waitall
    statuses = []

    begin
      while true
        statuses << Process.wait2
      end
    rescue Errno::ECHILD
    end

    statuses
  end

  def self.wait(pid=-1, flags=nil)
    pid, status = Process.wait2(pid, flags)
    return pid
  end

  class << self
    alias_method :waitpid, :wait
    alias_method :waitpid2, :wait2
  end

  def self.daemon(stay_in_dir=false, keep_stdio_open=false)
    # Do not run at_exit handlers in the parent
    exit!(0) if fork

    Process.setsid

    exit!(0) if fork

    Dir.chdir("/") unless stay_in_dir

    unless keep_stdio_open
      io = File.open "/dev/null", File::RDWR, 0
      $stdin.reopen io
      $stdout.reopen io
      $stderr.reopen io
    end

    return 0
  end

  def self.exec(*args)
    Rubinius::Mirror::Process.exec(*args)
  end

  def self.spawn(*args)
    Rubinius::Mirror::Process.spawn(*args)
  end

  # TODO: Should an error be raised on ECHILD? --rue
  #
  # TODO: This operates on the assumption that waiting on
  #       the event consumes very little resources. If this
  #       is not the case, the check should be made WNOHANG
  #       and called periodically.
  #
  def self.detach(pid)
    raise ArgumentError, "Only positive pids may be detached" unless pid > 0

    thread = Thread.new { Process.wait pid; $? }
    thread[:pid] = pid
    def thread.pid; self[:pid] end

    thread
  end

  def self.coerce_rlimit_resource(resource)
    case resource
    when Integer
      return resource
    when Symbol, String
      # do nothing
    else
      unless r = Rubinius::Type.check_convert_type(resource, String, :to_str)
        return Rubinius::Type.coerce_to resource, Integer, :to_int
      end

      resource = r
    end

    constant = "RLIMIT_#{resource}"
    unless const_defined? constant
      raise ArgumentError, "invalid resource name: #{constant}"
    end
    const_get constant
  end

  class << self
    private :coerce_rlimit_resource
  end

  #--
  # TODO: Most of the fields aren't implemented yet.
  # TODO: Also, these objects should only need to be constructed by
  # Process.wait and family.
  #++

  class Status

    attr_reader :termsig
    attr_reader :stopsig

    def initialize(pid=nil, status=nil, termsig=nil, stopsig=nil)
      @pid = pid
      @status = status
      @termsig = termsig
      @stopsig = stopsig
    end

    private :initialize

    def exitstatus
      @status
    end

    def to_i
      @status
    end

    def to_s
      @status.to_s
    end

    def &(num)
      @status & num
    end

    def ==(other)
      other = other.to_i if other.kind_of? Process::Status
      @status == other
    end

    def >>(num)
      @status >> num
    end

    def coredump?
      false
    end

    def exited?
      @status != nil
    end

    def pid
      @pid
    end

    def signaled?
      @termsig != nil
    end

    def stopped?
      @stopsig != nil
    end

    def success?
      if exited?
        @status == 0
      else
        nil
      end
    end
  end

  module Sys
    class << self
      def getegid
        ret = FFI::Platform::POSIX.getegid
        Errno.handle if ret == -1
        ret
      end

      def geteuid
        ret = FFI::Platform::POSIX.geteuid
        Errno.handle if ret == -1
        ret
      end

      def getgid
        ret = FFI::Platform::POSIX.getgid
        Errno.handle if ret == -1
        ret
      end

      def getuid
        ret = FFI::Platform::POSIX.getuid
        Errno.handle if ret == -1
        ret
      end

      def issetugid
        raise "not implemented"
      end

      def setgid(gid)
        gid = Rubinius::Type.coerce_to gid, Integer, :to_int

        ret = FFI::Platform::POSIX.setgid gid
        Errno.handle if ret == -1
        nil
      end

      def setuid(uid)
        uid = Rubinius::Type.coerce_to uid, Integer, :to_int

        ret = FFI::Platform::POSIX.setuid uid
        Errno.handle if ret == -1
        nil
      end

      def setegid(egid)
        egid = Rubinius::Type.coerce_to egid, Integer, :to_int

        ret = FFI::Platform::POSIX.setegid egid
        Errno.handle if ret == -1
        nil
      end

      def seteuid(euid)
        euid = Rubinius::Type.coerce_to euid, Integer, :to_int

        ret = FFI::Platform::POSIX.seteuid euid
        Errno.handle if ret == -1
        nil
      end

      def setrgid(rgid)
        setregid(rgid, -1)
      end

      def setruid(ruid)
        setreuid(ruid, -1)
      end

      def setregid(rid, eid)
        rid = Rubinius::Type.coerce_to rid, Integer, :to_int
        eid = Rubinius::Type.coerce_to eid, Integer, :to_int

        ret = FFI::Platform::POSIX.setregid rid, eid
        Errno.handle if ret == -1
        nil
      end

      def setreuid(rid, eid)
        rid = Rubinius::Type.coerce_to rid, Integer, :to_int
        eid = Rubinius::Type.coerce_to eid, Integer, :to_int

        ret = FFI::Platform::POSIX.setreuid rid, eid
        Errno.handle if ret == -1
        nil
      end

      def setresgid(rid, eid, sid)
        rid = Rubinius::Type.coerce_to rid, Integer, :to_int
        eid = Rubinius::Type.coerce_to eid, Integer, :to_int
        sid = Rubinius::Type.coerce_to sid, Integer, :to_int

        ret = FFI::Platform::POSIX.setresgid rid, eid, sid
        Errno.handle if ret == -1
        nil
      end

      def setresuid(rid, eid, sid)
        rid = Rubinius::Type.coerce_to rid, Integer, :to_int
        eid = Rubinius::Type.coerce_to eid, Integer, :to_int
        sid = Rubinius::Type.coerce_to sid, Integer, :to_int

        ret = FFI::Platform::POSIX.setresuid rid, eid, sid
        Errno.handle if ret == -1
        nil
      end
    end
  end

  module UID
    class << self
      def change_privilege(uid)
        uid = Rubinius::Type.coerce_to uid, Integer, :to_int

        ret = FFI::Platform::POSIX.setreuid(uid, uid)
        Errno.handle if ret == -1
        uid
      end

      def eid
        ret = FFI::Platform::POSIX.geteuid
        Errno.handle if ret == -1
        ret
      end

      def eid=(uid)
        uid = Rubinius::Type.coerce_to uid, Integer, :to_int

        ret = FFI::Platform::POSIX.seteuid(uid)
        Errno.handle if ret == -1
        uid
      end
      alias_method :grant_privilege, :eid=

      def re_exchange
        real = FFI::Platform::POSIX.getuid
        Errno.handle if real == -1
        eff = FFI::Platform::POSIX.geteuid
        Errno.handle if eff == -1
        ret = FFI::Platform::POSIX.setreuid(eff, real)
        Errno.handle if ret == -1
        eff
      end

      def re_exchangeable?
        true
      end

      def rid
        ret = FFI::Platform::POSIX.getuid
        Errno.handle if ret == -1
        ret
      end

      def sid_available?
        true
      end

      def switch
        eff = re_exchange
        if block_given?
          ret = yield
          re_exchange
          return ret
        else
          return eff
        end
      end

    end
  end

  module GID
    class << self
      def change_privilege(gid)
        gid = Rubinius::Type.coerce_to gid, Integer, :to_int

        ret = FFI::Platform::POSIX.setregid(gid, gid)
        Errno.handle if ret == -1
        gid
      end

      def eid
        ret = FFI::Platform::POSIX.getegid
        Errno.handle if ret == -1
        ret
      end

      def eid=(gid)
        gid = Rubinius::Type.coerce_to gid, Integer, :to_int

        ret = FFI::Platform::POSIX.setegid(gid)
        Errno.handle if ret == -1
        gid
      end
      alias_method :grant_privilege, :eid=

      def re_exchange
        real = FFI::Platform::POSIX.getgid
        Errno.handle if real == -1
        eff = FFI::Platform::POSIX.getegid
        Errno.handle if eff == -1
        ret = FFI::Platform::POSIX.setregid(eff, real)
        Errno.handle if ret == -1
        eff
      end

      def re_exchangeable?
        true
      end

      def rid
        ret = FFI::Platform::POSIX.getgid
        Errno.handle if ret == -1
        ret
      end

      def sid_available?
        true
      end

      def switch
        eff = re_exchange
        if block_given?
          ret = yield
          re_exchange
          return ret
        else
          return eff
        end
      end

    end
  end
end
