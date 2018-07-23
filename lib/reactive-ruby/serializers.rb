[TrueClass, FalseClass, NilClass, Float, String, Symbol, Time].each do |klass|
  klass.send(:define_method, :react_serializer) { as_json }
end
# Ruby 2.4 unifies Fixnum and Bignum into Integer
# and prints a warning if the old constants are accessed.
if 0.class == Integer
  Integer.send(:define_method, :react_serializer) { as_json }
else
  Fixnum.send(:define_method, :react_serializer) { as_json }
  Bignum.send(:define_method, :react_serializer) { as_json }
end

BigDecimal.send(:define_method, :react_serializer) { as_json } rescue nil

Array.send(:define_method, :react_serializer) do 
  self.collect { |e| e.react_serializer }.as_json
end

Hash.send(:define_method, :react_serializer) do
  Hash[*self.collect { |key, value| [key, value.react_serializer] }.flatten(1)].as_json
end
