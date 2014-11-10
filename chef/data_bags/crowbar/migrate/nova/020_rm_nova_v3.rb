def upgrade ta, td, a, d
  a.delete 'enable_v3_api'
  return a, d
end

def downgrade ta, td, a, d
  a['enable_v3_api'] = ta['enable_v3_api']
  return a, d
end
