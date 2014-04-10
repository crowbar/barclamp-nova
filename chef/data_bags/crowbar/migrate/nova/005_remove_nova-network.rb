def upgrade ta, td, a, d
  a.delete 'networking_backend'
  a.delete 'network'
  return a, d
end

def downgrade ta, td, a, d
  a['networking_backend'] = ta['networking_backend']
  a['network'] = ta['network']
  return a, d
end
