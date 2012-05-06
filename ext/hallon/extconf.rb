require 'mkmf'

# Miscellaneous
def error(message)
  abort "[ERROR] #{message}"
end

def command(cmd)
  $stderr.puts "execute '#{cmd}' ..."
  raise cmd unless system(cmd)
  $stderr.puts "execute '#{cmd}' done"
end

# Compilation Flags. Not absolutely necessary, but may save you a headache.
$DLDFLAGS << " -framework Foundation"
$CFLAGS << ' -ggdb -O0 -Wextra'

error 'Missing ruby header' unless have_header 'ruby.h'

create_makefile('coreaudio_ext')

# command "mv -f Makefile Makefile.bak"
# command "sed -e 's/^\.c\.o:$/\.m\.o:/' Makefile.bak > Makefile"
# command "rm Makefile.bak"
