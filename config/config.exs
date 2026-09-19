import Config

if config_env() == :test do
  config :atomic_bucket,
    test_env: true
end
