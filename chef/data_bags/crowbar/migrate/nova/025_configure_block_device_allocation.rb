def upgrade(ta, td, a, d)
  unless a.has_key? "block_device"
    a["block_device"] = ta["block_device"]
  end
  return a, d
end

def downgrade(ta, td, a, d)
  unless ta.has_key? "block_device"
    a.delete("block_device")
  end
  return a, d
end
