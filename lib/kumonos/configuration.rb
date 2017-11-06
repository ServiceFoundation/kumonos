module Kumonos
  class Configuration < Struct.new(:version, :ds, :statsd, :listener, :admin)
    class << self
      def from_hash(h)
        new(
          h.fetch('version'),
          symbolize_keys(h.fetch('ds')),
          symbolize_keys(h.fetch('statsd')),
          symbolize_keys(h.fetch('listener')),
          symbolize_keys(h.fetch('admin'))
        )
      end

      private

      def symbolize_keys(hash)
        new = hash.map do |k,v|
          [
            k.to_sym,
            Hash === v ? symbolize_keys(v) : v
          ]
        end
        new.to_h
      end
    end
  end
end
