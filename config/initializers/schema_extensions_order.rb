# db/schema.rb lists extensions alphabetically, but pgrouting requires
# postgis, so loading the schema into an empty database would fail. Dump
# postgis first.
ActiveSupport.on_load(:active_record) do
  ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaDumper.prepend(Module.new do
    private

    def extensions(stream)
      extensions = @connection.extensions
      return if extensions.empty?

      stream.puts "  # These are extensions that must be enabled in order to support this database"
      extensions.sort_by { |extension| [ { "pg_catalog.plpgsql" => 0, "postgis" => 1 }.fetch(extension, 2), extension ] }.each do |extension|
        stream.puts "  enable_extension #{extension.inspect}"
      end
      stream.puts
    end
  end)
end
