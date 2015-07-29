def upgrade ta, td, a, d
  a["block_device_allocate_retries"] = ta["block_device_allocate_retries"]
  a["block_device_allocate_retries_interval"] = ta["block_device_allocate_retries_interval"]
  return a, d
end

def downgrade ta, td, a, d
  a.delete "block_device_allocate_retries"
  a.delete "block_device_allocate_retries_interval"
  return a, d
end
