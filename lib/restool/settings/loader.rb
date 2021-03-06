require 'yaml'

require_relative 'models'

module Restool
  module Settings
    module Loader
      include Restool::Settings::Models

      DEFAULT_TIMEOUT    = 60
      DEFAULT_SSL_VERIFY = false


      def self.load(service_name)
        service_config = config['services'].detect do |service|
          service['name'] == service_name
        end

        raise "Service #{service_name} not found in configuration" unless service_config

        build_service(service_config)
      end

      private

      def self.build_service(service_config)
        representations = if service_config['representations']
                            build_representations(service_config['representations'])
                          else
                            []
                          end

        basic_auth = service_config['basic_auth'] || service_config['basic_authentication']
        basic_auth = BasicAuthentication.new(basic_auth['user'], basic_auth['password']) if basic_auth

        persistent_connection = service_config['persistent']
        persistent_connection = if persistent_connection
                                  PersistentConnection.new(
                                    persistent_connection['pool_size'],
                                    persistent_connection['warn_timeout'],
                                    persistent_connection['force_retry'],
                                  )
                                end

        # Support host + common path in url config, e.g. api.com/v2/
        paths_prefix_in_host = URI(service_config['url']).path

        Models::Service.new(
          service_config['name'],
          service_config['url'],
          service_config['operations'].map { |operation| build_operation(operation, paths_prefix_in_host) },
          persistent_connection,
          service_config['timeout'] || DEFAULT_TIMEOUT,
          representations,
          basic_auth,
          service_config['ssl_verify'] || DEFAULT_SSL_VERIFY
        )
      end

      def self.build_representations(representations)
        representations_by_name = {}

        representations.each do |representation|
          fields = representation[1].map do |field|
            RepresentationField.new(field['key'],
                              field['metonym'],
                              field['type'].to_sym)
          end

          representation = Representation.new(name = representation.first, fields)
          representations_by_name[representation.name.to_sym] = representation
        end

        representations_by_name
      end

      def self.build_operation(operation_config, paths_prefix_in_host)
        response = build_operation_response(operation_config['response']) if operation_config['response']

        path = operation_config['path']
        path = path[1..-1] if path[0] == '/'
        paths_prefix_in_host.chomp!('/')

        Operation.new(
          operation_config['name'],
          "#{paths_prefix_in_host}/#{path}",
          operation_config['method'],
          uri_params(operation_config),
          response
        )
      end

      def self.build_operation_response(response)
        response_fields = response.map do |field|
                            OperationResponsField.new(field['key'], field['metonym'], field['type'].to_sym)
                          end

        OperationResponse.new(response_fields)
      end

      def self.uri_params(operation_config)
        operation_config['path'].scan(/:[a-zA-Z_]+[0-9]*[a-zA-Z_]*/)
      end

      def self.config
        return @config if @config

        files_to_load = Dir['config/restool/*'] + ['config/restool.yml', 'config/restool.json']

        @config = { 'services' => [] }

        files_to_load.each do |file_name|
          next unless File.exist?(file_name)

          extension = File.extname(file_name)

          content = if extension == '.yml'
            YAML.load_file(file_name)
          elsif extension == '.json'
            json_file = File.read(file_name)
            JSON.parse(json_file)
          end

          @config['services'] += content['services']
        end

        @config
      end

      def self.validate
        # TODO: perform validations
      end

    end
  end
end
