def upgrade ta, td, a, d
  unless a.has_key? "force_config_drive"
    a["force_config_drive"] = ta["force_config_drive"]
  end
  return a, d
end

def downgrade ta, td, a, d
  unless ta.has_key? "force_config_drive"
    a.delete("force_config_drive")
  end
  return a, d
end
