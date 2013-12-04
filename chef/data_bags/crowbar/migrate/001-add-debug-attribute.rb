def upgrade ta, td, a, d
  a['debug'] = false
  return a, d
end

def downgrade ta, td, a, d
  a.delete['debug']
  return a, d
end
