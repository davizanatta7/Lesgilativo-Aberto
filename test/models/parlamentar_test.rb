require "test_helper"

class ParlamentarTest < ActiveSupport::TestCase
  test "valida campos obrigatorios e escopos" do
    dep = Parlamentar.create!(
      external_id: "999001",
      casa: "camara",
      nome: "Deputado Teste",
      partido: "PT",
      uf: "SP"
    )

    sen = Parlamentar.create!(
      external_id: "999002",
      casa: "senado",
      nome: "Senador Teste",
      partido: "PSD",
      uf: "RJ"
    )

    assert dep.deputado?
    assert sen.senador?
    assert_includes Parlamentar.por_casa("camara"), dep
    assert_not_includes Parlamentar.por_casa("camara"), sen
    assert_includes Parlamentar.por_uf("sp"), dep
    assert_includes Parlamentar.por_partido("psd"), sen
  end
end

