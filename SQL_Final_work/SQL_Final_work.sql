-- 1. В каких городах больше одного аэропорта?

select city ->> 'ru' as city, count(airport_code)
from airports_data
group by city ->> 'ru'
having count(airport_code) > 1;


-- 2. В каких аэропортах есть рейсы, выполняемые самолетом с максимальной дальностью перелета?

  -- найдем самолет с максимальной дальностью перелета
  -- выведем рейсы, выполняемые этим самолетом

select flight_no, departure_airport, departure_airport_name, arrival_airport, arrival_airport_name, aircraft_code
from routes
where aircraft_code in (
	select aircraft_code
	from aircrafts_data
	order by "range" desc limit 1);

  -- выведем аэропорты, в которых осуществляются эти рейсы

select departure_airport as airport, departure_airport_name as airport_name
from routes
where aircraft_code in (
	select aircraft_code
	from aircrafts_data
	order by "range" desc limit 1)
union
select arrival_airport, arrival_airport_name
from routes
where aircraft_code in (
	select aircraft_code
	from aircrafts_data
	order by "range" desc limit 1);


-- 3. Вывести 10 рейсов с максимальным временем задержки вылета.

select 
	flight_id, 
	flight_no, 
	scheduled_departure, 
	actual_departure, 
	(actual_departure - scheduled_departure) as difference
from flights
where actual_departure is not null
order by difference desc
limit 10;


-- 4. Были ли брони, по которым не были получены посадочные талоны?
  
select distinct a.book_ref
from (
	select a.book_ref, b.ticket_no, c.flight_id, d.boarding_no
	from bookings as a
	left join tickets as b on b.book_ref = a.book_ref
	left join ticket_flights as c on c.ticket_no = b.ticket_no
	left join boarding_passes as d on d.ticket_no = c.ticket_no and d.flight_id = c.flight_id
	where d.boarding_no is null) as a;
	
	
-- 5. Найдите свободные места для каждого рейса, их % отношение к общему количеству мест в самолете.
--    Добавьте столбец с накопительным итогом - суммарное количество вывезенных пассажиров из аэропорта за день. 
--    Т.е. в этом столбце должна отражаться сумма - сколько человек уже вылетело из данного аэропорта на этом 
--    или более ранних рейсах за день.

  -- Выведем для каждого рейса список занятых мест
  -- Сгруппируем данные по flight_id, чтобы посчитать количество занятых мест по каждому из них
  -- Посчитаем общее количество мест для каждой модели самолета
  -- Объединим данные этих запросов
  -- Посчитаем количество свободных мест для каждого рейса 
  -- (разница между общим количеством мест и количеством занятых мест)
  -- Посчитаем долю свободных мест в общем количестве мест, округлим результат до 2 знаков после запятой
  -- Посчитаем количество вывезенных пассажиров (по количеству занятых мест) по каждому аэропорту
  -- С накоплением по дате вылета (сколько человек улетело этим или более ранним рейсом за день из данного аэропорта)

select 
	aa.flight_id, aa.departure_airport, aa.actual_departure,
	aa.aircraft_code, 
	bb.all_seats, aa.busy_seats, 
	(bb.all_seats-aa.busy_seats) as free_seats,
	round((((bb.all_seats-aa.busy_seats)/bb.all_seats::float)*100)::numeric,2) as percent_free,
	sum(aa.busy_seats) over (partition by aa.departure_airport, aa.actual_departure::date order by aa.actual_departure) as passengers
from (
	select a.flight_id, a.aircraft_code, count(b.seat_no) as busy_seats, a.departure_airport, a.actual_departure
	from flights as a
	left join boarding_passes as b on b.flight_id = a.flight_id
	group by a.flight_id, a.aircraft_code
	order by a.flight_id) as aa
left join (
	select aircraft_code, count(seat_no) as all_seats
	from seats
	group by aircraft_code) as bb on bb.aircraft_code = aa.aircraft_code
order by aa.departure_airport, aa.actual_departure;


-- 6. Найдите процентное соотношение перелетов по типам самолетов от общего количества.

select 
	aircraft_code,
	count(flight_id) as count_flights,
	round((count(flight_id)/(select count(flight_id) from flights)::float*100)::numeric,2) as percentage
from flights
group by aircraft_code
order by percentage desc;


-- 7. Были ли города, в которые можно  добраться бизнес - классом дешевле, чем эконом-классом в рамках перелета?

  -- выведем в одном запросе перелеты (flight_id) с минимальной стоимостью билета бизнес-класса по каждому
  -- а в другом запросе перелеты (flight_id) с максимальной стоимостью билета эконом-класса по каждому
  -- соединим запросы по flight_id 
  -- (inner join, так как нас интересуют только те перелеты, по которым есть и билеты бизнес, и билеты эконом-класса)
  -- отфильтруем строки по условию, чтобы минимальная стоимость билета бизнес-класса была меньше 
  -- чем максимальная стоимость билета эконом-класса
  -- таких flight_id нет

with 
	cte_1 as (
			select flight_id, max(amount) as max_economy
			from ticket_flights
			where fare_conditions = 'Economy'
			group by flight_id
			order by flight_id), 
	cte_2 as (
			select flight_id, min(amount) as min_business
			from ticket_flights
			where fare_conditions = 'Business'
			group by flight_id
			order by flight_id),
	cte_3 as (
			select flight_id, arrival_city
			from flights_v) 
select c1.flight_id, c1.max_economy, c2.min_business, c3.arrival_city
from cte_1 as c1
inner join cte_2 as c2 on c2.flight_id = c1.flight_id
inner join cte_3 as c3 on c3.flight_id = c2.flight_id and c3.flight_id = c1.flight_id
where c2.min_business < c1.max_economy
	
  -- ОТВЕТ: таких перелетов, в рамках которых можно было бы добраться в какой-либо город 
  --        бизнес-классом дешевле, чем эконом-классом НЕТ

	
-- 8. Между какими городами нет прямых рейсов?

  -- создадим представление для всех возможных прямых рейсов между городами
  -- 101 уникальный город вылета и прилета, в итоге 101 * 100 = 10100 маршрутов
  
create view all_routess as (
	select distinct a.departure_city, b.arrival_city
	from routes as a, routes as b
	where a.departure_city != b.arrival_city
	order by a.departure_city, b.arrival_city)
	
  -- найдем, между какими городами нет прямых рейсов
 
select departure_city, arrival_city
from all_routess
except
select departure_city, arrival_city
from routes
order by departure_city, arrival_city;

  -- всего 9 584 маршрутов между городами, для которых нет прямых рейсов


-- 9. Вычислите расстояние между аэропортами, связанными прямыми рейсами.
--    Сравните с допустимой максимальной дальностью перелетов в самолетах, обслуживающих эти рейсы.

  -- вывели все прямые маршруты между аэропортами
  -- присоединили информацию по координатам аэропортов
  -- разделили координаты по столбцам на долготу / широту
  -- перевели координаты из градусов в радианы с помощью функции radians
  -- посчитали по формуле расстояние между аэропортами в радианах
  -- посчитали расстояние в километрах
  -- сравнили это расстояние с максимальной дальностью полета самолета

select 
	aa.departure_airport, aa.arrival_airport,
	acos(sin(aa.latitude_a)*sin(aa.latitude_b)+cos(aa.latitude_a)*cos(aa.latitude_b)*cos(aa.longitude_a - aa.longitude_b)) as d,
	acos(sin(aa.latitude_a)*sin(aa.latitude_b)+cos(aa.latitude_a)*cos(aa.latitude_b)*cos(aa.longitude_a - aa.longitude_b)) * 6371 as l,
	bb."range",
	(bb."range"-(acos(sin(aa.latitude_a)*sin(aa.latitude_b)+cos(aa.latitude_a)*cos(aa.latitude_b)*cos(aa.longitude_a - aa.longitude_b)) * 6371)) as difference
from (
	select 
		a.departure_airport, a.arrival_airport, 
		radians(b.coordinates[0]) as longitude_a,
		radians(b.coordinates[1]) as latitude_a,
		radians(c.coordinates[0]) as longitude_b,
		radians(c.coordinates[1]) as latitude_b,
		a.aircraft_code
	from routes as a
	left join airports_data as b on b.airport_code = a.departure_airport
	left join airports_data as c on c.airport_code = a.arrival_airport) as aa
left join aircrafts_data as bb on aa.aircraft_code = bb.aircraft_code;