def upgrade(ta, td, a, d)
  # NOTE(toabctl): we do nothing here because all the added keys
  # are not required
  return a, d
end

def downgrade(ta, td, a, d)
  unless ta["db"].key? "max_pool_size"
    a["db"].delete "max_pool_size"
  end
  unless ta["db"].key? "min_pool_size"
    a["db"].delete "min_pool_size"
  end
  unless ta["db"].key? "max_overflow"
    a["db"].delete "max_overflow"
  end
  unless ta["db"].key? "pool_timeout"
    a["db"].delete "pool_timeout"
  end
  return a, d
end
