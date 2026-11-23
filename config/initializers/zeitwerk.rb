# CodeGenerators::MetadataDSL lives in metadata_dsl.rb; Zeitwerk's default
# inflector expects MetadataDsl, which breaks eager loading (zeitwerk:check).
Rails.autoloaders.each do |autoloader|
  autoloader.inflector.inflect("metadata_dsl" => "MetadataDSL")
end
